#!/usr/bin/env python3
"""Shared local/CI commands. Raw compiler/test output stays in ignored local files."""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MANUAL_TESTS = [
    'GlobalCoordinatorTests/nativePagesInstantiateInBothAppearancesWithoutStartingSpeech()',
    'GlobalCoordinatorTests/compactPagesAccommodateLargerTextWithoutExpandingTheMinimumWindow()',
    'GlobalCoordinatorTests/compactDefaultHomeAndWindowUpdatesPreserveUserGeometryWithoutVoice()',
    'SettingsRowLayoutTests/actualNativeControlFramesShareTrailingEdge()',
]


# Milestone 38L3: speech failure/recovery plus retained 38L1/L2 regressions; four graphical checks stay manual.
MIN_APP_CASES = 1374
MIN_MODEL_LAB_TESTS = 152
REQUIRED_APP_TESTS = {
    'TeluguCoordinatorTests/rejectedRecognitionNeverReachesTheInsertionService(_:)',
    'TeluguCoordinatorTests/teluguStartupShowsPreparationUntilAudioIsReadyAndEnglishStaysQuiet()',
    'TeluguCoordinatorTests/oldPreferencesDefaultToExistingEnglishAndRoundTripNewMode()',
    'TeluguCoordinatorTests/routerDefaultsToEnglishAndAgentIgnoresTeluguSelection()',
    'TeluguCoordinatorTests/realInsertionServiceReceivesRomanisedTextOnceAfterRelease()',
    'TeluguCoordinatorTests/cancelledTeluguCannotInsertThroughLateCompletionOrNextSession()',
    'TeluguCoordinatorTests/missingModelHasActionableMessageAndNoInsertion()',

    'BravePortableContractTests/reviewedIdentityAndUntrustedTitleStayLiteralInProductionTemplate()',
    'PersonalCloseR3Tests/earlierSuccessfulQuitCannotHideALaterPendingQuit()',
    'PersonalCloseR3Tests/slowQuitReleasesForegroundThenReadOnlyObserverConfirms()',
    'PersonalCloseR3Tests/scopedLateProofCompletesOriginalOnlyAndNeverRunsRemainingSteps()',
    'PersonalCloseR3Tests/genericAgentFailurePillNeverStartsDictation()',
    'PersonalCloseR3Tests/lateProofDoesNotReplaceNewFnRecordingOrInsertAgentText()',
    'PersonalNaturalR2Tests/naturalRequestsWorkWithUnavailableModelAndZeroInferenceBudget()',
    'PersonalNaturalR2Tests/nativeAppPriorityAndExplicitWebsiteDisambiguation()',
    'PersonalNaturalR2Tests/literalNoteAndMessageRepliesDoNotBecomeOpenCommands()',
    'PersonalNaturalR2Tests/unknownWebsiteNeedsExactAddressWithoutGuessing()',
    'PersonalWebsiteR1Tests/agentSnapshotsExecuteOnceWithoutInsertion()',
    'PersonalWebsiteR1Tests/searchesAndLiteralRepliesRetainRepeatedWords()',
    'PersonalWebsiteR1Tests/targetBrowserAndAppIdentityArePreserved()',
    'PersonalAgent45CatalogTests/catalogIsExactlyTheFrozen100UniqueIDs()',
    'PersonalAgent45SafetyTests/pauseAndContinueNeverReplayVerifiedOrCreateTwoContinuations()',
    'PersonalAgent45ContextTests/savedRoutineRunAndEditUseRealContextWithoutAutoexecution()',
    'PersonalAgent45ContextTests/schedulingBindsExactPendingMessageAndRequestsSpecificTime()',

    'ActivationIdentity38L3R3Tests/eventPredatingActivationCannotBindToTheNewForegroundApp()',
    'ActivationIdentity38L3R3Tests/immutableOriginRejectsOtherAppsRelaunchesAndActivationChanges()',
    'ActivationIdentity38L3R3Tests/mailboxGenerationInvalidatesQueuedPressEvenAfterAppReturns()',
    'ActivationIdentity38L3R3Tests/nativeCaptureRejectsMissingOriginBeforeAnyEditorAXRead()',
    'ActivationIdentity38L3R3Tests/boundCaptureCannotSilentlyUseAnUnboundConformer()',
    'ActivationIdentity38L3R3Tests/matchingPressOriginIsCapturedOnceBeforeRecording()',
    'ActivationIdentity38L3R3Tests/focusSwitchBeforeCapturePreservesTranscriptWithoutAnyDispatch()',

    'SpeechRange38L3R2Tests/legacyMetadataCannotRoundAnOverlappingBoundaryIntoAnAppend()',
    'SpeechRange38L3R2Tests/overlappingModernRevisionPreservesUnaffectedBeginningAndEnd()',
    'SpeechRange38L3R2Tests/revisedFullPhraseMayMoveBothTimeBoundaries()',
    'SpeechRange38L3R2Tests/emptyModernRevisionRevokesOnlyItsAudioRange()',
    'SpeechRange38L3R2Tests/finalizationMetadataCommitsUnchangedEarlierVolatileSpeech()',
    'SpeechRange38L3R2Tests/genuinelyConflictingFinalCannotRewriteCommittedSpeech()',
    'SpeechRange38L3R2Tests/invalidTimebasesAreRejectedTransactionally()',
    'SpeechRange38L3R2Tests/sampleExactBoundaryNeedsNoArbitraryTolerance()',
    'SpeechRange38L3R2Tests/legacyRevisedHypothesisDoesNotAppendItsEarlierWordsTwice()',
    'SpeechRange38L3R2Tests/modernRecordingRevisionsPreserveWholeTranscript(seconds:)',
    'SpeechRange38L3R2Tests/overlapInSilenceInsertsBetweenTimedWords()',
    'SpeechRange38L3R2Tests/finalizationMaySplitPriorVolatilePhraseAtVerifiedWordBoundary()',
    'SpeechRange38L3R2Tests/zeroLengthVolatileHypothesisIsNotPrematurelyCommitted()',
    'SpeechRange38L3R2Tests/partialFinalizationInsideUntimedWordFailsWithoutLosingEarlierText()',

    'LegacyPassage38L3Tests/thirtySecondResetDoesNotTerminateHeldCapture()',
    'LegacyPassage38L3Tests/confirmedMetadataBoundaryPreservesEarlierWordsAndRepetitions()',
    'LegacyPassage38L3Tests/metadataPassagesWithPausesHaveNoMissingOrDuplicateSegments(seconds:)',
    'LegacyPassage38L3Tests/pendingBoundaryCanBeResolvedByLaterPublicMetadata()',
    'LegacyPassage38L3Tests/overlappingAnchorNeverAuthorizesAutomaticAppend()',
    'SpeechFailure38L3Tests/nativeLegacyDeliveryPreservesFIFOAcrossActorHop()',
    'SpeechFailure38L3Tests/nativeLegacyDeliveryOverflowReportsFailureInsteadOfCompletingFragment()',
    'SpeechFailure38L3Tests/legacyCodesRetainTheirProviderSpecificMeaning(_:)',
    'SpeechFailure38L3Tests/metadataNeverIncludesDescriptionsOrPrivateUserInfo()',
    'SpeechFailure38L3Tests/callbackPreservesNativeErrorAcrossActorHop()',
    'SpeechFailure38L3Tests/secondaryNativeInputFailsBeforeMicrophoneOrPermissions()',
    'SpeechFailure38L3Tests/releaseDrainsResamplerTailBeforeEndingSequence()',
    'SpeechFailure38L3Tests/providerFinalBeforeReleaseCannotBecomeSuccessAfterActorDelay()',
    'SpeechRecovery38L3Tests/failureWhileHeldRetainsFullAvailableSnapshotWithoutInsertion(_:_:)',
    'SpeechRecovery38L3Tests/releaseWaitsForLateTranscriptAndOneCompletion(_:)',
    'SpeechRecovery38L3Tests/ambiguousCandidateIsExplicitRecoveryNeverJoinedOrLogged()',
    'SpeechResources38L2Tests/statusRequiresBothInventoryAndInstalledLocale(_:)',
    'SpeechResources38L2Tests/inspectionNeverInstallsOrPrepares()',
    'SpeechResources38L2Tests/explicitInstallReportsProviderProgressAndThenPrepares()',
    'SpeechResources38L2Tests/failedInstallationCannotAdvertiseReadiness(_:)',
    'SpeechResources38L2Tests/preparationFailuresNeverClaimReady(_:)',
    'SpeechResources38L2Tests/installedLocaleAloneDoesNotProveModuleReadiness()',
    'GlobalCoordinatorTests/resourceInstallationIsExplicitAndPreparesWithoutRecordingOrInsertion()',
    'GlobalCoordinatorTests/stoppedResourceWaitCannotPublishLateSuccessOrStartCapture()',
    'GlobalCoordinatorTests/networkBlockingCannotBeBypassedBySpeechInstallAction()',
    'HeldSpeech38Tests/longCancellationAndMidRecordingPausesNeverInsert(_:)',
    'LongSpeech38Tests/orderedFinalPhrasesSurviveVolatileRevisions(_:)',
    'LongSpeech38Tests/syntheticPCMStreamsWithBoundedConsumerWithoutMicrophone(_:)',
    'LongSpeech38Tests/finalBoundaryCannotBeReplacedByLatestPartial()',
    'LongSpeech38Tests/legacyPassageAfterSilenceRetainsEarlierSpeechAndDefersUnverifiedReset()',
    'LongSpeech38Tests/narrowOverlappingPassageCannotEraseEarlierPrefix()',
    'HeldSpeech38Tests/heldSessionNeverStopsOrInsertsBeforeRelease(_:)',
    'HeldSpeech38Tests/providerEndWhileHeldRetainsTextWithoutAnyInsertion()',
    'GlobalHistoryTests/maximumLongDictationReopensWithoutCorruptingHistory()',
    'VoiceParityFormattingTests/spellingNeverChangesAnAsciiSuffixInsideUnicodeWord()',
    'VoiceParityFormattingTests/commonTyposWorkWithoutAnAppleSuggestionAndKeepProtectedTerms()',
    'OfflineQualityV2Tests/spokenPromptUsesRelevantSectionsWithoutNewContent()',
    'OfflineQualityV2Tests/opaqueSpansAreNotSplitAndWordsAreRetained()',
    'OfflineQualityV2Tests/boundedSegmentationAndInvalidPlanFailClosed()',
    'OfflineQualityV2Tests/toneGatePreservesNegationAndRejectsInventedRequirements(_:)',
    'OfflineQualityV2Tests/evaluationDatasetIsVersionedAndContractsAreAdmissible()',
    'QualityPreviewRejectionTests/rejectingCompletedPreviewRetainsInputAndNeverCopies()',
    'GlobalPreviewDeliveryTests/repeatsAndConsecutiveGestures(_:)',
    'GlobalPreviewDeliveryTests/invalidationCannotCompleteOldPress(_:)',
    'GlobalPreviewDeliveryTests/cancelledGestureAndUnknownOriginFailClosed()',
    'GlobalAIShortcutWorkflowTests/emptyInputShowsOnlyDisabledHUDWithoutEffects(_:)',
    'GlobalAIShortcutWorkflowTests/rapidChordsSleepAndLateResultsNeverReplaceSource()',
    'GlobalAIShortcutWorkflowTests/nativePanelNeverBecomesKeyOrMain()',
    'InPlaceRewriteTests/everyShortcutBranchMakesZeroPreviewRequests(_:_:)',
    'InPlaceRewriteTests/expiryReleasesRecordWithoutShortcutAndCannotDeliverLateAI()',
    'InsertionReadbackRepairTests/delayedTextEditLikeReadbackVerifiesWithoutSecondEffect(_:)',
    'ContinuousHUDTests/bothPostSpeechStagesKeepTheRequestedTranscriptionLabel()',
    'CoreDelivery37Tests/identityBoundPasteDoesNotRequireAnExactOriginal(_:)',
    'CoreDelivery37Tests/unsafeOpaqueTargetCannotReceiveAnyEvent(_:)',
    'CoreDelivery37Tests/opaqueTargetCannotUseUnverifiableTypingWhenClipboardIsUnsupported()',
    'CoreDelivery37Tests/sameOwnershipRevisionCannotHideAChangedClipboardPayload()',
    'CoreDelivery37Tests/noExactContextCreatesNoAIReceiptAndPreservesHistoryAndPipelineState()',
    'CoreDelivery37Tests/cancelWhilePreDispatchClockIsSuspendedCannotPaste()',
    'CoreDelivery37Tests/postPublicationMismatchPreservesNewDataWithoutDispatch()',
}


def version(text):
    match = re.search(r'(\d+)\.(\d+)', text)
    if not match:
        raise ValueError('version-unavailable')
    return tuple(map(int, match.groups()))


def preflight(env):
    developer = Path(env.get('DEVELOPER_DIR', ''))
    if not developer.is_absolute() or not developer.is_dir() or not str(developer).endswith('.app/Contents/Developer'):
        raise ValueError('Select a full Xcode with DEVELOPER_DIR')
    def output(command):
        return subprocess.check_output(command, env=env, stderr=subprocess.DEVNULL, text=True)
    xcode = output(['/usr/bin/xcodebuild', '-version'])
    swift = output(['/usr/bin/xcrun', 'swift', '--version'])
    sdk = output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version'])
    if (platform.machine() != 'arm64' or version(platform.mac_ver()[0]) < (26, 0)
            or version(xcode) != (27, 0) or version(swift) < (6, 4) or version(sdk) < (27, 0)):
        raise ValueError('Requires arm64 macOS26+, Xcode27.0, Swift6.4+ and macOS27+ SDK')
    if sys.version_info < (3, 11):
        raise ValueError('Python3.11+ required')
    return {'xcode': '.'.join(map(str, version(xcode))), 'swift': '.'.join(map(str, version(swift))),
            'sdk': '.'.join(map(str, version(sdk))), 'architecture': platform.machine()}


def xcode_command(action, directory):
    common = ['/usr/bin/xcodebuild', '-project', 'WesleyFlow.xcodeproj', '-scheme', 'WesleyFlow',
              '-destination', 'platform=macOS,arch=arm64', '-derivedDataPath', str(directory / 'DerivedData'),
              '-disableAutomaticPackageResolution', '-skipPackageUpdates', '-jobs', '2',
              'ONLY_ACTIVE_ARCH=YES', 'ARCHS=arm64', 'COMPILER_INDEX_STORE_ENABLE=NO',
              'DEBUG_INFORMATION_FORMAT=dwarf']
    if action == 'test':
        return common + ['-configuration', 'Debug', '-parallel-testing-enabled', 'NO',
                         '-resultBundlePath', str(directory / 'tests.xcresult'), 'test'] + [
            '-skip-testing:WesleyFlowAppTests/' + test for test in MANUAL_TESTS]
    return common + ['-configuration', 'Debug' if action == 'debug' else 'Release'] + (
        ['SWIFT_STRICT_CONCURRENCY=complete'] if action == 'concurrency' else []) + ['build']


def run(command, env, log):
    with log.open('w') as stream:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=1200)
    return result.returncode



def gui_executed(node):
    if isinstance(node, dict):
        if node.get("nodeIdentifier") in MANUAL_TESTS and node.get("result") not in (None, "Skipped"):
            return True
        return any(gui_executed(value) for value in node.values())
    return isinstance(node, list) and any(gui_executed(value) for value in node)


def passed_identifiers(node):
    if isinstance(node, dict):
        result = {node['nodeIdentifier']} if node.get('result') == 'Passed' and 'nodeIdentifier' in node else set()
        for value in node.values():
            result.update(passed_identifiers(value))
        return result
    if isinstance(node, list):
        return set().union(*(passed_identifiers(value) for value in node))
    return set()


def require_test_results(data, tree):
    cases = sum(item['passedTests'] for item in data['devicesAndConfigurations'])
    if cases < MIN_APP_CASES or data['failedTests'] or data['result'] != 'Passed':
        raise ValueError('test-count-or-result')
    if gui_executed(tree):
        raise ValueError('manual-test-exclusion-not-honored')
    if not REQUIRED_APP_TESTS.issubset(passed_identifiers(tree)):
        raise ValueError('required-integration-regressions-not-passed')
    return cases



def failure_diagnostics(log, result_bundle=None, env=None):
    """Only static source locations/categories and declaration IDs leave the runner."""
    text = log.read_text(errors='replace') if log.is_file() else ''
    diagnostics = {}
    categories = set()
    locations = []
    for match in re.finditer(r'(?m)^([^:\n]+\.swift):(\d+):\d+:\s+error:\s+(.+)$', text):
        # A source filename is useful; local paths, source lines and diagnostic text stay private.
        name = Path(match[1]).name
        if re.fullmatch(r'[A-Za-z0-9_.-]{1,100}\.swift', name):
            locations.append({'file': name, 'line': int(match[2])})
        message = match[3].lower()
        if 'unable to type-check' in message:
            categories.add('swift-type-check-timeout')
        elif 'has no member' in message or 'cannot find' in message:
            categories.add('swift-missing-symbol')
        elif 'isolation' in message or 'sendable' in message:
            categories.add('swift-concurrency')
        else:
            categories.add('swift-compile')
    for needle, category in [('CodeSign failed', 'code-signing'),
                             ('Failed to establish communication', 'test-host-communication'),
                             ('Failed to launch', 'test-host-launch'),
                             ('Testing cancelled because the build failed', 'build-failed')]:
        if needle in text:
            categories.add(category)
    if result_bundle and result_bundle.exists():
        try:
            result = subprocess.run(['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(result_bundle)],
                                    env=env, capture_output=True, timeout=60)
            if not result.returncode:
                declarations = set()
                def visit(node):
                    if isinstance(node, dict):
                        identifier = node.get('nodeIdentifier', '')
                        if (node.get('result') == 'Failed' and isinstance(identifier, str)
                                and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*\([A-Za-z0-9_:, ]*\)', identifier)):
                            declarations.add(identifier)
                        for value in node.values():
                            visit(value)
                    elif isinstance(node, list):
                        for value in node:
                            visit(value)
                visit(json.loads(result.stdout))
                if declarations:
                    diagnostics['failedDeclarations'] = sorted(declarations)[:20]
                    categories.add('test-assertion')
        except (OSError, ValueError, subprocess.SubprocessError):
            categories.add('test-result-unavailable')
    if categories:
        diagnostics['categories'] = sorted(categories)
    if locations:
        diagnostics['sourceLocations'] = locations[:12]
    return diagnostics

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['preflight', 'test', 'debug', 'release', 'concurrency', 'model-lab'])
    parser.add_argument('--output', type=Path, default=ROOT / 'Evidence/CI/local')
    args = parser.parse_args()
    env = os.environ.copy()
    env.pop('SDKROOT', None)
    if env.get('CI') == 'true':
        # No artifacts/cache uploads; never emit raw logs, result bundles or paths.
        directory = Path(tempfile.mkdtemp(prefix='wesley-ci-', dir=env.get('RUNNER_TEMP')))
    else:
        directory = args.output.resolve()
        directory.mkdir(parents=True, exist_ok=True)
    summary = {'action': args.action, 'result': 'FAILED'}
    try:
        summary['toolchain'] = preflight(env)
        code = 0
        if args.action == 'model-lab':
            commands = [[sys.executable, 'ModelLab/build_validator.py'],
                        [sys.executable, '-m', 'unittest', 'discover', '-s', 'ModelLab/tests', '-v'],
                        [sys.executable, '-m', 'unittest', 'discover', '-s', 'ModelLab/NativeDiagnostics', '-p', 'test_*.py', '-v']]
        elif args.action == 'preflight':
            commands = []
        else:
            commands = [xcode_command(args.action, directory)]
        for index, command in enumerate(commands):
            code = run(command, env, directory / f'{args.action}-{index}.log')
            if args.action == 'model-lab' and index > 0 and not code:
                match = re.search(r'^Ran (\d+) tests? in ', (directory / f'{args.action}-{index}.log').read_text(errors='replace'), re.MULTILINE)
                count = int(match.group(1)) if match else 0
                summary['modelLabTests' if index == 1 else 'resourceGuardTests'] = count
                if count < (MIN_MODEL_LAB_TESTS if index == 1 else 7):
                    code = 1
            if code:
                break
        if code:
            summary['exitCode'] = code
            summary['failureDetails'] = failure_diagnostics(directory / f'{args.action}-{index}.log', directory / 'tests.xcresult' if args.action == 'test' else None, env)
        elif args.action == 'test':
            command = ['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(directory / 'tests.xcresult')]
            result = subprocess.run(command, env=env, capture_output=True, timeout=60)
            if result.returncode:
                raise ValueError('test-summary-unavailable')
            data = json.loads(result.stdout)
            tree_result = subprocess.run(['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(directory / 'tests.xcresult')], env=env, capture_output=True, timeout=60)
            if tree_result.returncode:
                raise ValueError('test-selection-unavailable')
            cases = require_test_results(data, json.loads(tree_result.stdout))
            summary.update(passedCases=cases, passedDeclarations=data['passedTests'], failed=data['failedTests'], result='PASSED')
        else:
            summary['result'] = 'PASSED'
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        # Do not echo exception/source lines, personal paths or private test text.
        summary['diagnostic'] = 'Toolchain or check failed; reproduce locally with the documented command.'
    (directory / f'{args.action}-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary))
    return summary['result'] != 'PASSED'


if __name__ == '__main__':
    sys.exit(main())
