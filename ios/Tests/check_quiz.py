"""Run real Swift quiz logic with public BIP39 fixtures; never reads Keychain."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
core = root / 'Ouryn/Core/QuizOptions.swift'
source = core.read_text()
store_source = (root / 'Ouryn/Core/Store.swift').read_text()
source += '\nstruct Noti: ' + store_source.split('struct Noti: ', 1)[1].split('\nstruct Schedule:', 1)[0]
tests = r'''
let legacy = Data(#"{"id":"n0","icon":"key","title":"지갑을 만들었어요","body":"열쇠는 이 폰 안에만 있어요","ts":0,"read":false}"#.utf8)
let decoded = try JSONDecoder().decode(Noti.self, from: legacy)
precondition(decoded.action == nil && !decoded.read)
let reminder = Noti(id: "backup-reminder", icon: "key", title: "복구 문구를 적어주세요", body: "종이에 적어두세요", ts: Date(), read: true, action: "recovery")
let roundTrip = try JSONDecoder().decode(Noti.self, from: JSONEncoder().encode(reminder))
precondition(roundTrip == reminder)

let words = "abandon ability able about above absent absorb abstract absurd abuse access accident".split(separator: " ").map(String.init)
for i in words.indices {
    for _ in 0..<100 {
        let opts = QuizOptions.get(i, words)
        guard opts.count == 6, Set(opts).count == 6 else { fatalError("Expected six unique choices") }
        guard opts.filter({ Set(words).contains($0) }) == [words[i]] else { fatalError("Distractors expose recovery words") }
    }
}
let repeated = Array(repeating: "abandon", count: 11) + ["about"]
let opts = QuizOptions.get(0, repeated)
precondition(opts.count == 6 && Set(opts).intersection(Set(repeated)) == ["abandon"])
precondition(QuizOptions.get(-1, words).isEmpty)
precondition(QuizOptions.get(12, words).isEmpty)
precondition(QuizOptions.get(0, []).isEmpty)
precondition(QuizOptions.get(0, ["not-a-bip39-word"]).isEmpty)

'''
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    resource = root / 'Ouryn/Resources/bip39-english.txt'
    if resource.exists():
        vocabulary = resource.read_text().split()
        assert len(vocabulary) == len(set(vocabulary)) == 2048
        (tmp / resource.name).write_text(resource.read_text())
        tests += '\nprecondition(Set(QuizOptions.englishWords).count == 2048)\n'
        tests += '\nprecondition(QuizOptions.get(0, words).allSatisfy { QuizOptions.englishWords.contains($0) })\n'
    (tmp / 'main.swift').write_text(source + tests)
    subprocess.run(['swiftc','-module-cache-path','/tmp/ouryn-swift-cache', str(tmp / 'main.swift'), '-o', str(tmp / 'quiz-tests')], check=True)
    subprocess.run([str(tmp / 'quiz-tests')], check=True)
    # Missing vocabulary must block confirmation, never fall back to private words.
    (tmp / resource.name).unlink()
    (tmp / 'main.swift').write_text(core.read_text() + '\nprecondition(QuizOptions.get(0, ["abandon", "about"]).isEmpty)\n')
    subprocess.run(['swiftc','-module-cache-path','/tmp/ouryn-swift-cache', str(tmp / 'main.swift'), '-o', str(tmp / 'missing-vocabulary-tests')], check=True)
    subprocess.run([str(tmp / 'missing-vocabulary-tests')], check=True)
    print("PASS: 1,200 randomized cases; repeated words; invalid indices; empty phrase; missing vocabulary fails closed; 2,048-word vocabulary; legacy notification decoding and action round-trip")
