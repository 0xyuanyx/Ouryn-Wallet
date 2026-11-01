"""Compile actual router logic on macOS; verify modal replacement waits for dismissal."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
router = (root / 'Ouryn/App/Router.swift').read_text()
pay = (root / 'Ouryn/Core/Pay.swift').read_text().split('struct PayRequest:', 1)[1].split('\n///', 1)[0]
source = router + '\nstruct PayRequest:' + pay
checks = '''
let router = Router()
router.present(.receive)
precondition(router.modal == .receive)
router.present(.fromExchange(asset: nil))
precondition(router.modal == nil, "Replacement must dismiss the old modal first")
'''
if 'func modalDidDismiss()' in router:
    checks += '''
router.present(.scan)
precondition(router.modal == nil, "A second request must still wait for dismissal")
router.modalDidDismiss()
precondition(router.modal == .scan)
router.modal = nil
router.modalDidDismiss()
precondition(router.modal == nil, "Dismissal must not reopen a stale pending modal")
router.present(.receive)
router.present(.receive)
precondition(router.modal == .receive, "Same modal should not close itself")
'''
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp)
    (p/'main.swift').write_text(source + checks)
    subprocess.run(['swiftc','-module-cache-path','/tmp/ouryn-swift-cache', str(p/'main.swift'), '-o', str(p/'test')], check=True)
    subprocess.run([str(p/'test')], check=True)
print('PASS: modal handoff, pending-state clearing, same-modal presentation')
