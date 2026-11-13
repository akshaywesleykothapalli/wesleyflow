#!/usr/bin/env python3
"""Offline, open-set speaker evaluation for Wesley Flow."""
import argparse
import ctypes as ct
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
import time
import wave

RATE = 16_000
MAX_FRAMES = 14 * RATE
MIN_FRAMES = RATE
SPLITS = ("calibration", "test")


@dataclass(frozen=True)
class Model:
    filename: str
    size: int
    sha256: str
    dimension: int


MODELS = {
    "b3": Model("b3-vox2-lm.onnx", 18_922_382,
                "64af443843678ddcc910172f7b6ff3aa7ddcb96041c3bc36d2c586674b4a59e9", 192),
    "resnet34": Model("wespeaker.onnx", 26_534_365,
                      "5ef208a9da1453335308a6b6f4e6dfbd7e183a38b604de0a57664f45d257fe94", 256),
    "ecapa": Model("voxceleb_ECAPA512_LM.onnx", 24_861_931,
                   "d71b85d9b48058ef68004f04f1b78acebefb9dfcf542e19b976a12a5ad1f10b0", 192),
    "b6": Model("b6-vox2-lm.onnx", 51_863_429,
                "f318e8f435ee35855284c1906d25beb9a34b1c3dcd902d5afa10b4639f0bc168", 192),
}


@dataclass(frozen=True)
class Clip:
    path: Path
    speaker: str
    session: str
    split: str
    role: str


def read_pcm(path):
    with wave.open(str(path)) as audio:
        if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) != (1, 2, RATE):
            raise ValueError("WAV input must be mono 16-bit PCM at 16 kHz")
        data = audio.readframes(min(audio.getnframes(), MAX_FRAMES))
    if len(data) < 2 * MIN_FRAMES:
        raise ValueError("WAV input must be at least one second")
    return data


def load_clips(path):
    manifest = json.loads(path.read_text())
    if manifest["kind"] not in ("synthetic", "human"):
        raise ValueError("Corpus kind must be synthetic or human")
    clips = []
    seen_audio = set()
    seen_speakers = {}
    for row in manifest["clips"]:
        clip = Clip((path.parent / row["path"]).resolve(), row["speaker"], row["session"],
                    row["split"], row["role"])
        if not clip.speaker or not clip.session or clip.split not in SPLITS:
            raise ValueError("Every clip requires a speaker, session and valid split")
        if clip.role not in ("enroll", "query"):
            raise ValueError("Clip role must be enroll or query")
        if seen_speakers.setdefault(clip.speaker, clip.split) != clip.split:
            raise ValueError("Speakers must be disjoint across calibration and test")
        digest = hashlib.sha256(read_pcm(clip.path)).digest()
        if digest in seen_audio:
            raise ValueError("Duplicate evaluated PCM in corpus")
        seen_audio.add(digest)
        clips.append(clip)

    for split in SPLITS:
        enrollment = {}
        for clip in clips:
            if clip.split == split and clip.role == "enroll":
                enrollment.setdefault(clip.speaker, []).append(clip.session)
        queries = [clip for clip in clips if clip.split == split and clip.role == "query"]
        genuine = {clip.speaker for clip in queries if clip.speaker in enrollment}
        unknown = {clip.speaker for clip in queries} - enrollment.keys()
        if genuine != enrollment.keys() or not genuine or not unknown:
            raise ValueError("Each split needs queries for every enrolled speaker and unseen speakers")
        if any(len(sessions) != 3 for sessions in enrollment.values()):
            raise ValueError("Use exactly three clips per enrolled profile")
        if any(clip.session in enrollment.get(clip.speaker, []) for clip in queries):
            raise ValueError("Enrollment and queries must use different sessions per speaker")
    return manifest["kind"], clips


def verified_model(path, spec):
    with path.open("rb") as model:
        data = model.read(spec.size + 1)
    if len(data) != spec.size or hashlib.sha256(data).hexdigest() != spec.sha256:
        raise ValueError(f"Model size or SHA-256 mismatch for {spec.filename}")
    return data


def normalize(vector):
    length = math.sqrt(sum(value * value for value in vector))
    if not math.isfinite(length) or length <= 0:
        raise ValueError("Invalid embedding")
    return tuple(value / length for value in vector)


def redim_features(pcm):
    import numpy as np

    # Matches the mediainbox v0.2.0 ReDimNet2 frontend. The FFT computes the
    # same Hamming-windowed bins as its DFT convolution.
    waveform = pcm.astype(np.float32) / 32768
    waveform = (waveform - waveform.mean()) / (waveform.std() + 1e-8)
    emphasized = waveform - .97 * np.pad(waveform, (1, 0), mode="reflect")[:-1]
    frames = np.lib.stride_tricks.sliding_window_view(np.pad(emphasized, 80), 400)[::160]
    spectrum = np.fft.rfft(frames * np.hamming(400).astype(np.float32), n=512)[:, :256]
    power = np.abs(spectrum) ** 2
    low, high = 2595 * np.log10(1 + np.array([20, 7600]) / 700)
    points = np.linspace(low, high, 74)
    bins = 2595 * np.log10(1 + np.linspace(0, RATE // 2, 256) / 700)[:, None]
    rising = (bins - points[:-2]) / (points[1:-1] - points[:-2])
    falling = (points[2:] - bins) / (points[2:] - points[1:-1])
    filters = np.maximum(0, np.minimum(rising, falling)).astype(np.float32)
    mel = np.log((power.clip(1e-8, 1e8) @ filters).clip(1e-8, 1e8) + 1e-8).T
    mel -= mel.mean(axis=1, keepdims=True)
    aligned = mel.shape[1] // 4 * 4
    return np.ascontiguousarray(mel[None, None, :, :aligned], dtype=np.float32)


def ecapa_features(pcm):
    import torch
    from torchaudio.compliance.kaldi import fbank

    # WeSpeaker's default Hamming Kaldi frontend, with PCM-scale samples and CMN.
    waveform = torch.tensor(pcm, dtype=torch.float32).unsqueeze(0)
    frames = fbank(waveform, sample_frequency=RATE, num_mel_bins=80,
                   frame_length=25, frame_shift=10, window_type="hamming")
    return (frames - frames.mean(dim=0)).unsqueeze(0).numpy()


def run_onnx(model_id, data, dimension, inputs):
    import numpy as np
    import onnxruntime as ort

    if model_id == "ecapa":
        import torch
        torch.set_num_threads(1)
        feature_fn, input_name = ecapa_features, "feats"
    else:
        feature_fn, input_name = redim_features, "features"

    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    start = time.perf_counter()
    session = ort.InferenceSession(data, options, providers=["CPUExecutionProvider"])
    load_ms = (time.perf_counter() - start) * 1000
    if [node.name for node in session.get_inputs()] != [input_name] or len(session.get_outputs()) != 1:
        raise ValueError("Unexpected ONNX graph input/output contract")
    vectors, times = [], []
    for raw in inputs:
        pcm = np.frombuffer(raw, dtype="<i2")
        start = time.perf_counter()
        vector, = session.run(None, {input_name: feature_fn(pcm)})
        times.append((time.perf_counter() - start) * 1000)
        if vector.shape != (1, dimension):
            raise ValueError("Unexpected ONNX embedding shape")
        vectors.append(normalize(vector[0].tolist()))
    return vectors, times, load_ms


def run_resnet(data, dimension, inputs, app, wrapper):
    import numpy as np

    lib = ct.CDLL(str(wrapper.resolve()))
    lib.WFSpeakerOpen.argtypes = [ct.c_char_p, ct.c_char_p, ct.c_int32]
    lib.WFSpeakerOpen.restype = ct.c_void_p
    lib.WFSpeakerClose.argtypes = [ct.c_void_p]
    float_ptr = ct.POINTER(ct.c_float)
    lib.WFSpeakerEmbed.argtypes = [ct.c_void_p, float_ptr, ct.c_int32, float_ptr, ct.c_int32]
    lib.WFSpeakerEmbed.restype = ct.c_int
    runtime = app / "Contents/Frameworks/libsherpa-onnx-c-api.dylib"
    with tempfile.TemporaryDirectory(prefix="wf-speaker-") as directory:
        artifact = Path(directory) / "verified.onnx"
        artifact.write_bytes(data)
        start = time.perf_counter()
        context = lib.WFSpeakerOpen(bytes(runtime.resolve()), bytes(artifact), dimension)
        load_ms = (time.perf_counter() - start) * 1000
        if not context:
            raise ValueError("The installed ResNet34 runtime could not load the pinned artifact")
        try:
            vectors, times = [], []
            output = (ct.c_float * dimension)()
            for raw in inputs:
                pcm = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768
                start = time.perf_counter()
                success = lib.WFSpeakerEmbed(context, pcm.ctypes.data_as(float_ptr), pcm.size,
                                             output, dimension)
                times.append((time.perf_counter() - start) * 1000)
                if not success:
                    raise ValueError("The installed ResNet34 runtime could not embed a clip")
                vectors.append(normalize(output))
            return vectors, times, load_ms
        finally:
            lib.WFSpeakerClose(context)


@dataclass(frozen=True)
class Trial:
    known: bool
    correct: bool
    score: float


def score_split(clips, vectors, split):
    profiles = {}
    for clip, vector in zip(clips, vectors, strict=True):
        if clip.split == split and clip.role == "enroll":
            profiles.setdefault(clip.speaker, []).append(vector)
    centers = {speaker: normalize([sum(column) for column in zip(*samples)])
               for speaker, samples in profiles.items()}
    trials = []
    for clip, vector in zip(clips, vectors, strict=True):
        if clip.split != split or clip.role != "query":
            continue
        scores = [(sum(a * b for a, b in zip(vector, center, strict=True)), speaker)
                  for speaker, center in centers.items()]
        score, winner = max(scores)
        unique = sum(value == score for value, _ in scores) == 1
        trials.append(Trial(clip.speaker in centers, unique and winner == clip.speaker,
                            score if unique else -math.inf))
    return trials


def calibrate(trials, target):
    unknown = sorted((trial.score for trial in trials if not trial.known), reverse=True)
    if not unknown or not 0 <= target < 1:
        raise ValueError("Calibration needs unknown queries and a target in [0, 1)")
    budget = math.floor(len(unknown) * target)
    return math.nextafter(unknown[budget], math.inf)


def outcomes(trials, threshold):
    result = dict(known=0, correct=0, known_unknown=0, wrong_name=0, unknown=0, false_names=0)
    for trial in trials:
        accepted = trial.score >= threshold
        if trial.known:
            result["known"] += 1
            if not accepted:
                result["known_unknown"] += 1
            elif trial.correct:
                result["correct"] += 1
            else:
                result["wrong_name"] += 1
        else:
            result["unknown"] += 1
            result["false_names"] += int(accepted)
    return result


def evaluate(args, kind, clips):
    spec = MODELS[args.model]
    path = (args.app / "Contents/Resources" if args.model == "resnet34" else args.models_dir) / spec.filename
    data = verified_model(path, spec)
    inputs = [read_pcm(clip.path) for clip in clips]
    if args.model == "resnet34":
        vectors, times, load_ms = run_resnet(data, spec.dimension, inputs, args.app, args.wrapper)
    else:
        vectors, times, load_ms = run_onnx(args.model, data, spec.dimension, inputs)
    calibration = score_split(clips, vectors, "calibration")
    test = score_split(clips, vectors, "test")
    threshold = calibrate(calibration, args.max_false_id)
    query_times = sorted(ms for clip, ms in zip(clips, times, strict=True)
                         if clip.split == "test" and clip.role == "query")
    return {
        "model": args.model, "model_sha256": spec.sha256, "corpus_kind": kind,
        "threshold": threshold, "calibration": outcomes(calibration, threshold),
        "test": outcomes(test, threshold), "load_ms": round(load_ms, 2),
        "test_query_p50_ms": round(statistics.median(query_times), 2),
        "test_query_p95_ms": round(query_times[math.ceil(.95 * len(query_times)) - 1], 2),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--models-dir", type=Path, required=True)
    parser.add_argument("--app", type=Path, default=Path("/Applications/Wesley Flow.app"))
    parser.add_argument("--wrapper", type=Path, help="CSpeakerRuntime dylib built from the repo")
    parser.add_argument("--max-false-id", type=float, default=.01)
    parser.add_argument("--model", choices=MODELS)
    args = parser.parse_args()
    if not 0 <= args.max_false_id < 1:
        parser.error("--max-false-id must be in [0, 1)")
    if args.model in (None, "resnet34") and args.wrapper is None:
        parser.error("--wrapper is required when running ResNet34")
    kind, clips = load_clips(args.manifest)
    if args.model:
        print(json.dumps(evaluate(args, kind, clips), allow_nan=False))
        return
    # A separate process per model keeps native loader failures and model memory isolated.
    rows = []
    for model in MODELS:
        child = subprocess.run([sys.executable, __file__, *sys.argv[1:], "--model", model],
                               capture_output=True, text=True)
        if child.returncode:
            raise SystemExit(f"{model} failed (exit {child.returncode}): {child.stderr.strip()}")
        rows.append(json.loads(child.stdout))
    incumbent = next(row["test"] for row in rows if row["model"] == "resnet34")
    allowed = math.floor(incumbent["unknown"] * args.max_false_id)
    for row in rows:
        result = row["test"]
        row["observed_improvement"] = (result["correct"] > incumbent["correct"]
                                       and result["false_names"] <= min(allowed, incumbent["false_names"]))
    print(json.dumps({"corpus_kind": kind, "host": platform.platform(),
                      "false_id_target": args.max_false_id, "results": rows}, indent=2))


if __name__ == "__main__":
    main()
