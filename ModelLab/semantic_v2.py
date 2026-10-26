"""V2 static source-contract benchmark, never a Swift interpreter or effect engine.

Semantic evidence is closed-set source equivalence to an authored reference, not
execution of behavioral examples. New algorithms outside that set remain unreviewed.
"""
import argparse,copy,json,re,uuid
from pathlib import Path
import lab
from calibration import metrics as structural_metrics

# Independently stated API/domain/example contracts for a new benchmark version.
# Examples are inert specification data, never evaluated as code.
SPECS=[
('func sum(_ a: Int, _ b: Int) -> Int','All Int inputs; overflow behavior has not been specified.',['(2,3) -> 5','(-2,2) -> 0']),
('func clamp(_ value: Int, lower: Int, upper: Int) -> Int','lower <= upper; inclusive bounds; no arithmetic overflow.',['(5,0,3) -> 3','(-2,0,3) -> 0','(2,0,3) -> 2']),
('func isEven(_ value: Int) -> Bool','All Swift Int values; zero and negative multiples of two are even.',['0 -> true','-4 -> true','-3 -> false']),
('func fahrenheit(_ celsius: Double) -> Double','Finite Double inputs; IEEE754 operations in order celsius * 9 / 5 + 32.',['0 -> 32','100 -> 212','-40 -> -40']),
('func divide(_ a: Double, by b: Double) -> Double?','Finite Double inputs; both signed zeros as denominator produce nil; otherwise IEEE754 division.',['(6,3) -> 2','(1,0) -> nil','(1,-0.0) -> nil']),
('func average(_ values: [Double]) -> Double?','Finite Double elements; empty -> nil; left-to-right Double sum divided by Double count.',['[] -> nil','[2,4] -> 3','[0] -> 0']),
('func countNonnegative(_ values: [Int]) -> Int','All Int elements; include zero and preserve no values, only count.',['[] -> 0','[-1,0,2] -> 2']),
('func positives(_ values: [Int]) -> [Int]','Strictly greater than zero; stable original order and duplicates.',['[-1,0,2,2,1] -> [2,2,1]','[] -> []']),
('func squares(_ values: [Int]) -> [Int]','All Int elements; overflow behavior has not been specified.',['[-2,0,3] -> [4,0,9]','[] -> []']),
('func largest(_ values: [Int]) -> Int?','All Int elements; empty array -> nil.',['[] -> nil','[-3,-1,-2] -> -1']),
('func reversedNames(_ values: [String]) -> [String]','Reverse array order, not the characters within each String; keep duplicates.',['["ab","cd"] -> ["cd","ab"]','[] -> []']),
('func unique(_ values: [String]) -> [String]','Swift String equality; stable first-occurrence order, case sensitive.',['["a","b","a","A"] -> ["a","b","A"]','[] -> []']),
('func element(_ values: [String], at index: Int) -> String?','All Int indices; return nil for negative or index >= count.',['(["a"],0) -> "a"','(["a"],-1) -> nil','([],0) -> nil']),
('func sentence(_ words: [String]) -> String','Join unmodified strings with exactly one ASCII space; keep empty elements.',['[] -> ""','["a","","b"] -> "a  b"']),
('func characterCount(_ text: String) -> Int','Swift Character / extended grapheme cluster count, not UTF8 bytes or Unicode scalar count.',['"" -> 0','"e\\u{301}" -> 1','"👨‍👩‍👧‍👦" -> 1']),
('func trimmed(_ text: String) -> String','Foundation CharacterSet.whitespacesAndNewlines at both ends only; keep internal whitespace.',['"  a b\\n" -> "a b"','"" -> ""']),
('func words(_ text: String) -> [String]','Split at Swift Character.isWhitespace; omit empty subsequences, preserve word characters.',['" a\\t b\\n" -> ["a","b"]','"" -> []']),
('func expandTabs(_ text: String) -> String','Replace every literal U+0009 with four ASCII spaces; not tab-stop alignment.',['"a\\tb" -> "a    b"','"x" -> "x"']),
('func secureURLPrefix(_ text: String) -> Bool','Literal case-sensitive prefix https:// only; no URL parsing or security validation.',['"https://x" -> true','"HTTPS://x" -> false','"http://x" -> false']),
('func removePeriod(_ text: String) -> String','Remove exactly one trailing ASCII period; leave all other characters unchanged.',['"a.." -> "a."','"." -> ""','"a" -> "a"']),
('struct ChecklistItem: Codable { let title: String; let completed: Bool }','Immutable stored title:String and completed:Bool; synthesized Codable with matching property keys.',['members title:String, completed:Bool are let','Codable conformance; no extra fields']),
('enum WorkState: Sendable { case pending, active, finished }','Exactly three cases named pending, active, finished; Sendable; no associated or raw values.',['exact case set pending/active/finished','Sendable conformance']),
('struct Point: Equatable { let x: Int; let y: Int }','Exactly two immutable stored Int coordinates x and y; synthesized memberwise Equatable.',['Point(x:1,y:2) equals same coordinates','changing x or y makes unequal']),
('enum Priority: Int { case low = 1, medium = 2, high = 3 }','Exactly three cases and explicit Int raw values low1, medium2, high3.',['low.rawValue -> 1','medium.rawValue -> 2','high.rawValue -> 3']),
('func displayName(_ nickname: String?) -> String','Only nil falls back to Guest; an empty or whitespace string is retained.',['nil -> "Guest"','"" -> ""','"Ada" -> "Ada"']),
('func humanPosition(_ position: Int) -> String','Zero-based Int position; negative and overflow behavior have not been specified.',['0 -> "1"','9 -> "10"']),
('func area(width: Double, height: Double) -> Double','Finite nonnegative inputs only; IEEE754 width times height; negative inputs outside V2 contract.',['(2,3) -> 6','(0,7) -> 0']),
('func isLeapYear(_ year: Int) -> Bool','Positive proleptic Gregorian years; divisible by400 or divisible by4 but not100.',['1900 -> false','2000 -> true','2024 -> true','2023 -> false']),
('func minuteParts(_ seconds: Int) -> (minutes: Int, seconds: Int)','Nonnegative seconds; quotient and remainder on division by60, named tuple fields.',['0 -> (0,0)','61 -> (1,1)','120 -> (2,0)']),
('func kilometers(_ meters: Double) -> Double','Finite Double meters; return IEEE754 meters / 1000; negative values retained.',['1000 -> 1','-500 -> -0.5','0 -> 0']),
('func middle(_ a: Int, _ b: Int, _ c: Int) -> Int','All Int inputs; median by total numeric order, preserving duplicate values.',['(3,1,2) -> 2','(2,2,1) -> 2']),
('func overlaps(_ a: ClosedRange<Int>, _ b: ClosedRange<Int>) -> Bool','Valid closed ranges; sharing an endpoint counts as overlap.',['(1...3,3...5) -> true','(1...2,3...4) -> false']),
('func position(of target: Int, in values: [Int]) -> Int?','First zero-based matching index; nil if absent; Swift Int equality.',['(2,[2,1,2]) -> 0','(9,[]) -> nil']),
('func allEnabled(_ flags: [Bool]) -> Bool','True exactly when all values true; empty collection is vacuously true.',['[] -> true','[true,false] -> false','[true,true] -> true']),
('func occurrences(of target: String, in values: [String]) -> Int','Count Swift String equality matches, case sensitive, including duplicates.',['("a",["a","A","a"]) -> 2','("x",[]) -> 0']),
('func partition(_ values: [Int]) -> (even: [Int], odd: [Int])','Int elements; remainder0 even, nonzero odd, including negatives; stable order within each named output.',['[-3,-2,0,1] -> ([-2,0],[-3,1])','[] -> ([],[])']),
('func byLength(_ values: [String]) -> [String]','Ascending Swift Character count, ties use native Swift String < (not localized collation); duplicates retained.',['["bb","a","b","aa"] -> ["a","b","aa","bb"]','[] -> []']),
('func flatten(_ values: [[Int]]) -> [Int]','Concatenate nested arrays in original outer and inner order; empty arrays contribute no elements.',['[[1],[],[2,3]] -> [1,2,3]','[] -> []']),
('func frequencies(_ values: [Int]) -> [Int: Int]','Count each distinct Int key; dictionary iteration order is irrelevant.',['[2,1,2] -> {1:1,2:2}','[] -> {}']),
('func products(_ a: [Int], _ b: [Int]) -> [Int]','Equal-length arrays specified; per-element Int multiplication overflow behavior unspecified.',['([2,3],[4,5]) -> [8,15]','([],[]) -> []']),
('func distance(_ a: Double, _ b: Double) -> Double','Finite Double inputs; IEEE754 abs(a-b), not integer absolute value.',['(1,4) -> 3','(2,2) -> 0']),
('func shorter(_ a: String, _ b: String) -> String','Swift Character counts; choose first argument on equal counts; return original string.',['("ab","cd") -> "ab"','("long","x") -> "x"']),
('func firstNonempty(_ values: [String]) -> String?','First string whose isEmpty is false; a whitespace-only string is nonempty; nil if none.',['[""," ","a"] -> " "','[""] -> nil','[] -> nil']),
('func lowercaseNames(_ values: [String]) -> [String]','Native Swift String.lowercased(), not locale-specific Turkish casing; preserve array order and count.',['["ABC","x"] -> ["abc","x"]','[] -> []']),
('func presentValues(_ values: [Int?]) -> [Int]','Remove only nil; keep zero, negatives, duplicates and original order.',['[nil,0,-1,nil,0] -> [0,-1,0]','[] -> []']),
('func validPercent(_ value: Int) -> Bool','Inclusive numeric interval0...100; all Int inputs.',['0 -> true','100 -> true','-1 -> false','101 -> false']),
('func totalCharacters(_ values: [String]) -> Int','Swift Character counts; sum/count-overflow and resource limits unspecified.',['["a","bc"] -> 3','[] -> 0']),
('func signName(_ value: Int) -> String','All Int values; return exact lowercase negative/zero/positive.',['-1 -> "negative"','0 -> "zero"','1 -> "positive"'])]
INCOMPLETE={1:'Int addition overflow policy is unspecified.',9:'Int square overflow policy is unspecified.',26:'Negative position and Int increment overflow policy are unspecified.',40:'Int product overflow policy is unspecified.',47:'Aggregate count overflow/resource policy is unspecified.'}
REJECTIONS=['Malformed or extra proposal schema fields','Wrong project/proposal/snapshot identity','Wrong target path or operation','Wrong expected file revision','Extra file changes','Content outside the frozen approved-source equivalence class','Unsupported tools, effects, self-approval or command fields']
TOKEN=re.compile(r'"(?:[^"\\\n]|\\.)*"|[A-Za-z_$][A-Za-z_0-9$]*|[0-9]+(?:\.[0-9]+)?|[^\s]',re.UNICODE)

def source_tokens(source):
    if not isinstance(source,str) or len(source.encode())>65536:raise lab.LabError('source assertion size/type')
    # Tokenization only; never evaluates Swift. Comments are not discarded.
    return TOKEN.findall(source)

def wire_row(case):
    return {'id':case['id'],'instruction':case['instruction'],'projectID':case['projectID'],'proposalID':case['proposalID'],
            'entries':case['projectTree'],'editableTargets':[case['targetRelativePath']],
            'expectedProposal':case['expectedProposal'],'expectedResponse':case['expectedResponse'],
            'expectedDisposition':case['expectedDisposition'],'split':case['split'],'family':case['family']}

def signature(case):
    return {'version':2,'caseID':case['id'],'sourceV1ID':case['sourceV1ID'],'split':case['split'],'status':case['status'],
            'caseSHA256':lab.digest(case),'projectID':case['projectID'],'proposalID':case['proposalID'],
            'workspaceRevision':case['workspaceRevision'],'target':case['targetRelativePath'],
            'operation':case['supportedOperation'],'expectedFileRevision':case['expectedFileRevision'],
            'contentSHA256':lab.digest(case['expectedContent'].encode()) if case['expectedContent'] is not None else None,
            'contentTokenSHA256':lab.digest(source_tokens(case['expectedContent'])) if case['expectedContent'] is not None else None,
            'refusalSHA256':lab.digest(case['expectedResponse'].encode()) if case['expectedDisposition']=='reject' else None}

def build_cases(original):
    if len(SPECS)!=48:raise lab.LabError('V2 specification count')
    cases=[]
    for index,row in enumerate(original,1):
        project=str(uuid.uuid5(uuid.NAMESPACE_URL,'WesleyFlow-ModelLab2A-project-'+row['id']))
        proposal=str(uuid.uuid5(uuid.NAMESPACE_URL,'WesleyFlow-ModelLab2A-proposal-'+row['id']))
        entries=copy.deepcopy(row['entries']);context={'projectID':project,'proposalID':proposal,'entries':entries,'editableTargets':row['editableTargets']}
        native=lab.bridge([context])[0];positive=row['expectedProposal'] is not None
        expected=copy.deepcopy(row['expectedProposal'])
        if positive:
            expected.update(projectID=project,proposalID=proposal,baseSnapshotDigest=native['snapshotDigest'])
            expected['changes'][0]['expectedRevision']=native['revisions'][entries[0]['relativePath']]
            api,domain,examples=SPECS[index-1];content=expected['changes'][0]['utf8Content'];operation=expected['changes'][0]['kind']
            instruction=row['instruction']+' Required Swift API: '+api+'. Input/behavior contract: '+domain+' Specification examples: '+'; '.join(examples)+'. Return one full-file proposal only; no extra declarations. Static scoring recognizes only the approved full-file source; LF or CRLF line endings are accepted; other source variants require separate review.'
            reason=INCOMPLETE.get(index)
            behavior={'api':api,'inputDomain':domain,'examples':examples,'examplesExecuted':False,'assertionMode':'approved-source-line-endings-v1','semanticScope':'static approved implementation contract; not arbitrary-program behavior proof'}
        else:
            content=None;operation='reject';instruction=row['instruction'];reason=None
            behavior={'api':None,'inputDomain':'Unsupported request; refuse without effects.','examples':[row['expectedResponse']],'examplesExecuted':False,'assertionMode':'exact-safe-refusal-v1','semanticScope':'literal protocol refusal only'}
        cases.append({'datasetVersion':2,'id':row['id'].replace('ml1-','ml2a-'),'sourceV1ID':row['id'],'sourceV1RowSHA256':lab.digest(row),
            'split':row['split'],'family':row['family'],'projectID':project,'proposalID':proposal,'projectTree':entries,
            'workspaceRevision':native['snapshotDigest'],'instruction':instruction,'supportedOperation':operation,'targetRelativePath':entries[0]['relativePath'],
            'expectedFileRevision':native['revisions'][entries[0]['relativePath']],'expectedContent':content,
            'expectedProposal':expected,'expectedResponse':lab.canonical(expected) if positive else row['expectedResponse'],
            'expectedDisposition':row['expectedDisposition'],'acceptableVariants':{'mode':'exact-source-with-LF-or-CRLF-line-endings' if positive else 'exact-refusal','unlistedAlgorithms':'UNREVIEWED, not proven incorrect'},
            'behaviorContract':behavior,'rejectionConditions':REJECTIONS,'status':'INCOMPLETE' if reason else 'COMPLETE','incompleteReason':reason,
            'review':'agent-authored/static-reference-reviewed; no compiler, behavioral execution or independent human review'})
    return cases

def semantic_score(case,response):
    row=wire_row(case);native=lab.bridge([lab.context(row,response)])[0];structural=structural_metrics(row,response,native)
    expected=case['expectedProposal'];parsed=None
    try:parsed=json.loads(response)
    except (ValueError,TypeError):pass
    if expected:
        changes=parsed.get('changes',[]) if isinstance(parsed,dict) else []
        text=changes[0].get('utf8Content') if isinstance(changes,list) and len(changes)==1 and isinstance(changes[0],dict) else None
        match=isinstance(text,str) and text.replace('\r\n','\n')==case['expectedContent']
        fields=['schemaValidity','projectIdentityCorrect','proposalIdentityCorrect','snapshotIdentityCorrect','targetPathCorrect','operationCorrect','expectedRevisionCorrect','validatorAccepted']
        structure=all(structural[k] is True for k in fields)
        semantic=match if case['status']=='COMPLETE' else None
        overall=(structure and match) if case['status']=='COMPLETE' else (None if structure else False)
        rejection=None
    else:
        match=None;structure=structural['schemaValidity'];semantic=None
        rejection=structural['unauthorizedOperationRejection'];overall=rejection
    return {'datasetVersion':2,'caseID':case['id'],'contractStatus':case['status'],'structural':structural,
            'structuralContractSatisfied':structure,'contentAssertionsCorrect':semantic,
            'approvedSourceMatch':match,'behavioralExamplesExecuted':False,'behavioralRuntimeCorrect':None,
            'rejectionCorrect':rejection,'overallTaskSuccess':overall,'scoringScope':case['behaviorContract']['semanticScope'],
            'unreviewedVariant':bool(expected and not match),'incompleteReason':case['incompleteReason']}

def prompt(case):
    return {'datasetVersion':2,'instruction':case['instruction'],'projectID':case['projectID'],'proposalID':case['proposalID'],
            'baseSnapshotDigest':case['workspaceRevision'],'authorizedSyntheticContext':case['projectTree'],
            'editableTargets':[case['targetRelativePath']],'revisions':{case['targetRelativePath']:case['expectedFileRevision']},
            'safeRefusal':'Cannot propose this request: unsupported or unauthorized operation.'}

def manifest(cases,original):
    return {'schemaVersion':2,'corpusFingerprint':lab.digest(cases),'sourceV1Fingerprint':lab.digest(original),
            'evaluationFingerprint':lab.digest([r for r in cases if r['split']=='test']),
            'splitAlgorithm':'inherit-v1-source-family-with-new-v2-identities; never combine versions for training',
            'splits':{s:{'ids':[r['id'] for r in cases if r['split']==s],
                'count':sum(r['split']==s for r in cases),'eligibleIDs':[r['id'] for r in cases if r['split']==s and r['status']=='COMPLETE'],
                'sha256':lab.digest([r for r in cases if r['split']==s])} for s in ['train','valid','test']},
            'signatures':[signature(r) for r in cases],'semantics':'closed-source-equivalence, not executable behavioral evaluation'}

def leakage(cases,original):
    # Ignore shared protocol/identity boilerplate. Use authored behavioral text and
    # reference code as in V1, plus exact reference-token duplicate detection.
    original_by_id={r['id']:r for r in original};duplicates=[];near=[]
    for i,a in enumerate(cases):
        for b in cases[i+1:]:
            if a['split']==b['split']:continue
            if a['expectedContent'] is not None and b['expectedContent'] is not None and source_tokens(a['expectedContent'])==source_tokens(b['expectedContent']):duplicates.append([a['id'],b['id']])
            if lab.near(original_by_id[a['sourceV1ID']],original_by_id[b['sourceV1ID']])>=0.8:near.append([a['id'],b['id']])
    # Refusal targets intentionally repeat; they are one shared protocol behavior,
    # not twelve independent learned semantics. Never claim their response isolation.
    return {'crossSplitExactCodingDuplicates':duplicates,'crossSplitNearDuplicates':near,'nearThreshold':0.8,
            'method':'V1 behavioral instruction + reference code token-set Jaccard; exclude protocol/identity boilerplate',
            'sharedRefusalTargetAcrossSplits':True,'semanticIndependenceProven':False}

def load_frozen():
    original=lab.jsonl(lab.ROOT/'data/corpus.jsonl');lab.verify_corpus(original,lab.read_json(lab.ROOT/'config/dataset-v1.json'))
    cases=lab.jsonl(lab.ROOT/'data/corpus-v2.jsonl');frozen=lab.read_json(lab.ROOT/'config/dataset-v2.json')
    if frozen!=manifest(cases,original):raise lab.LabError('frozen V2 manifest or signatures changed')
    if len(cases)!=60 or len({r['id'] for r in cases})!=60:raise lab.LabError('V2 case identity/count')
    by_id={r['id']:r for r in original}
    for case in cases:
        source=by_id[case['sourceV1ID']]
        if case['split']!=source['split'] or case['family']!=source['family'] or case['sourceV1RowSHA256']!=lab.digest(source):raise lab.LabError('V2 held-out/source binding')
        if case['status'] not in ['COMPLETE','INCOMPLETE'] or (case['status']=='INCOMPLETE')!=bool(case['incompleteReason']):raise lab.LabError('V2 status')
    analysis=leakage(cases,original)
    if analysis['crossSplitExactCodingDuplicates'] or analysis['crossSplitNearDuplicates']:raise lab.LabError('V2 leakage detected')
    return cases,frozen,analysis

def one_admission_gate(observe,weight_bytes,execute):
    """Exactly one initial observation; no retry. Executor owns monitoring if admitted.

    Tests inject inert executors. Not a command-line inference entry point.
    """
    decision=lab.admission(observe(),weight_bytes)
    if not decision['admitted']:return {'state':'BLOCKED','admission':decision,'executed':False}
    return execute(decision)

def audit():
    cases,frozen,analysis=load_frozen();scores=[semantic_score(r,r['expectedResponse']) for r in cases]
    expected={'COMPLETE':55,'INCOMPLETE':5}
    if {k:sum(r['status']==k for r in cases) for k in expected}!=expected:raise lab.LabError('V2 quality count changed')
    result={'state':'STATIC CONTRACT REPLAY VERIFIED','datasetVersion':2,'fingerprint':frozen['corpusFingerprint'],
            'scores':scores,'counts':{'codingComplete':43,'codingIncomplete':5,'refusalComplete':12,
                'staticReferenceSuccess':sum(r['overallTaskSuccess'] is True for r in scores),'unscoredIncomplete':sum(r['overallTaskSuccess'] is None for r in scores)},
            'leakage':analysis,'modelInference':False,'codeExecuted':False,'behavioralRuntimeCoverage':0,
            'trainingEligible':{s:sum(r['split']==s and r['status']=='COMPLETE' and r['expectedProposal'] is not None for r in cases) for s in ['train','valid','test']}}
    lab.write_json(lab.ROOT.parent/'Evidence/ModelLab2A/frozen-replay.json',result)
    print(lab.canonical({k:result[k] for k in ['state','counts','trainingEligible','modelInference','codeExecuted']}))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--responses',type=Path);args=parser.parse_args()
    if args.responses:
        cases,_,_=load_frozen();index={r['id']:r for r in cases};records=lab.jsonl(args.responses)
        if len({r['caseID'] for r in records})!=len(records):raise lab.LabError('duplicate V2 score identity')
        for record in records:
            if set(record)!={'caseID','response'} or record['caseID'] not in index or not isinstance(record['response'],str):raise lab.LabError('V2 response schema')
            print(lab.canonical(semantic_score(index[record['caseID']],record['response'])))
    else:audit()
if __name__=='__main__':main()
