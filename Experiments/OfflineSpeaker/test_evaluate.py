import json
from pathlib import Path
import tempfile
import unittest
import wave

from evaluate import Clip, Trial, calibrate, load_clips, outcomes, score_split


class EvaluationTests(unittest.TestCase):
    def test_unknown_threshold_is_conservative_at_ties(self):
        trials = [Trial(False, False, score) for score in (.8, .8, .4, .1)]
        threshold = calibrate(trials, .25)
        self.assertEqual(outcomes(trials, threshold)["false_names"], 0)
        self.assertEqual(outcomes(trials, calibrate(trials, .5))["false_names"], 2)

    def test_outcomes_distinguish_rejection_from_wrong_name(self):
        trials = [
            Trial(True, True, .8), Trial(True, False, .9), Trial(True, True, .2),
            Trial(False, False, .9), Trial(False, False, .2),
        ]
        self.assertEqual(outcomes(trials, .5), {
            "known": 3, "correct": 1, "known_unknown": 1,
            "wrong_name": 1, "unknown": 2, "false_names": 1,
        })

    def test_unenrolled_query_scores_against_all_profiles_and_ties_abstain(self):
        clips = [Clip(Path("a.wav"), "a", "enroll", "test", "enroll"),
                 Clip(Path("b.wav"), "b", "enroll", "test", "enroll"),
                 Clip(Path("query.wav"), "c", "query", "test", "query")]
        vectors = [(1, 0), (0, 1), (.6, .8)]
        self.assertEqual(score_split(clips, vectors, "test"), [Trial(False, False, .8)])
        vectors[-1] = (.5, .5)
        self.assertEqual(outcomes(score_split(clips, vectors, "test"), .4)["false_names"], 0)

    def test_manifest_requires_disjoint_speakers_sessions_and_audio(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rows = []
            for split in ("calibration", "test"):
                for index, role in enumerate(("enroll", "enroll", "enroll", "query", "query")):
                    path = f"{split}-{index}.wav"
                    with wave.open(str(root / path), "wb") as audio:
                        audio.setparams((1, 2, 16000, 16000, "NONE", ""))
                        audio.writeframes(bytes([len(rows), 0]) * 16000)
                    rows.append(dict(path=path, speaker=f"{split}-{index == 4}", split=split,
                                     role=role, session=role))
            manifest = root / "corpus.json"

            def save():
                manifest.write_text(json.dumps(dict(kind="synthetic", clips=rows)))

            save()
            self.assertEqual(len(load_clips(manifest)[1]), 10)
            for key, value, message in [
                ("speaker", rows[3]["speaker"], "disjoint"),
                ("session", "enroll", "different sessions"),
                ("path", rows[0]["path"], "Duplicate"),
            ]:
                with self.subTest(key=key):
                    original = rows[8][key]
                    rows[8][key] = value
                    save()
                    with self.assertRaisesRegex(ValueError, message):
                        load_clips(manifest)
                    rows[8][key] = original


if __name__ == "__main__":
    unittest.main()
