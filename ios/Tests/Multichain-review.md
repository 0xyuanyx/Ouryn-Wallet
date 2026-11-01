# Multichain verification — 2026-10-02

- Ouryn + OurynWidgets build: `xcodebuild build -quiet -project ios/Ouryn.xcodeproj -scheme Ouryn -destination 'platform=iOS Simulator,id=CCBB0978-6AB9-48D4-8EC8-A7A31959CA67' -derivedDataPath /tmp/ouryn-multichain-build CODE_SIGNING_ALLOWED=NO` — exit 0.
- Four Foundation executables: registry/exact amounts; Tron immutable draft; Bitcoin raw transaction outputs; Cardano raw CBOR body/outputs — PASS.
- Existing `check_scan.py`, `check_startup.py`, `check_p1.py`, `check_quiz.py` — PASS, including 1,200 randomized quiz cases.
- DEBUG simulator launch `--multichain-diagnostics --network-diagnostics` — 34 PASS, 0 FAIL. Full report: `multichain-diagnostics.txt`.
- Includes public seven-network derivation/address/QR checks, wrong-chain parsing, old state decoding, published WalletCore Tron/Ethereum/Solana signing vectors, Cardano published raw transaction hash/address/value conservation, and all seven public mainnet APIs.
- Independent review identified key replacement loss, SOL overflow, expired pending blockage, retry wallet race, batched receipt deduplication, and Cardano selected-input conservation. All reported findings were corrected. Runtime mainnet checks also caught a truncated Solana genesis identifier and a Bitcoin provider timeout; full genesis hash and Esplora fallback resolved both.
- Public tests reference Apache-2.0 [WalletCore Swift tests](https://github.com/trustwallet/wallet-core/tree/master/swift/Tests/Blockchains). They use published fixtures only, never user recovery material.

## Limits

No XCTest target was created; pure production code is compiled into Swift test executables and SDK checks run in the DEBUG simulator diagnostics. No real user transfer, testnet broadcast, or funded mainnet transaction was executed. Broadcast/status implementations and preflight are compiled; server identity checks do not prove successful funded transfers. Camera permissions and Face ID require device checks. The registered iPhone was `unavailable` in devicectl, so no device install occurred.

The full older implementation plan also proposes paginated receive history for every chain, actual fee enrichment and testnet end-to-end checks. Those remain follow-up work; current implementation includes hash-based send tracking for every chain and recent confirmed Tron USDT receipts. Savings and automatic sends remain disabled.
