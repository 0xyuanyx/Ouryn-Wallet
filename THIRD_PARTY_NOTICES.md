# 제3자 구성 요소 고지 (Third-Party Notices)

Ouryn 앱과 저장소에 포함되거나 앱이 사용하는 제3자 구성 요소입니다. 각 구성 요소는 아래 라이선스를 따릅니다.

| 구성 요소 | 버전 | 라이선스 | 저장소 안 위치 | 출처 |
|---|---|---|---|---|
| Trust Wallet Core | 4.8.3 (`Package.resolved` 고정 revision `5031fe6d…`) | Apache-2.0 | Swift Package 의존성 (저장소에 포함하지 않음) | https://github.com/trustwallet/wallet-core |
| Pretendard | 번들된 OTF 4종 (Regular·Medium·SemiBold·Bold) | SIL Open Font License 1.1 | `ios/Ouryn/Resources/Pretendard-*.otf`, 라이선스 원문 `ios/Ouryn/Resources/Pretendard-LICENSE.txt` | https://github.com/orioncactus/pretendard |
| Ionicons | 번들된 `Ionicons.ttf` · `Ionicons.json` | MIT | `ios/Ouryn/Resources/Ionicons.*`, 라이선스 원문 `ios/Ouryn/Resources/Ionicons-LICENSE.txt` | https://github.com/ionic-team/ionicons |
| BIP39 영어 단어 목록 | Wallet Core의 trezor-crypto 사본 | MIT | `ios/Ouryn/Resources/bip39-english.txt`, 라이선스 `ios/Ouryn/Resources/bip39-LICENSE.txt` | https://github.com/trustwallet/wallet-core |
| cryptocurrency-icons | 코인 SVG (아래 메모 참고) | CC0 1.0 | `assets/coins/`, `ios/Ouryn/Assets.xcassets/coin-*`, 라이선스 `assets/coins/LICENSE-cryptocurrency-icons.md` | https://github.com/spothq/cryptocurrency-icons |

## 메모

- Pretendard·Ionicons 라이선스 원문은 2026-11-01에 각 프로젝트의 기본 브랜치에서 받은 것입니다. 번들된 폰트·아이콘 파일의 정확한 배포 버전은 기록돼 있지 않아서, 다음에 파일을 바꿀 때 버전을 함께 적어주세요.
- 라이선스 원문 파일은 `ios/Ouryn/` 아래에 있어 앱 번들에도 함께 들어갑니다.
- 코인 SVG의 고지 파일은 cryptocurrency-icons(CC0)를 가리키지만, 그 세트에 없을 수 있는 아이콘(예: `mnt`, `night`)도 있어 파일별 출처를 확인해야 합니다. 저작권 라이선스와 별개로, 각 코인·토큰 로고(USDC·USDT 등)는 해당 프로젝트·발행사의 상표일 수 있습니다.
- Trust Wallet Core는 빌드할 때 Swift Package Manager가 받습니다. Wallet Core가 함께 쓰는 구성 요소(SwiftProtobuf, trezor-crypto 등)의 고지는 Wallet Core 저장소의 LICENSE·NOTICE를 따릅니다.
- Ouryn 자체 코드의 라이선스(LICENSE)는 아직 정하지 않았습니다. 저장소를 공개하기 전에 정해서 루트에 넣어야 합니다.
