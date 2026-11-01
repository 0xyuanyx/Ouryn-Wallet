# 다중 네트워크 지갑 구현

## 지원 범위

| 네트워크 | 받기·보내기 자산 | 수수료 자산 |
|---|---|---|
| Tron | USDT(TRC-20), TRX | TRX |
| Solana | USDC, USDT, SOL | SOL |
| Ethereum | USDC, USDT, ETH | ETH |
| Mantle | MNT, USDT0 | MNT |
| Avalanche C-Chain | USDC, USDT, AVAX | AVAX |
| Bitcoin | BTC | BTC |
| Cardano | ADA, NIGHT(네이티브 토큰) | ADA |

맨틀 USDT0는 USDT와 다른 자산으로 표시한다. 공식 계약은 [USDT0 Mantle](https://usdt0.to/ecosystem/mantle)에서 확인했다. 맨틀 USDC 및 임의 브리지 토큰은 추가하지 않았다. NIGHT는 카르다노 네이티브 자산이며 Midnight 프라이버시 지갑은 아니다.

## 사용

받기에서 네트워크와 코인을 선택하면 해당 네트워크의 주소 및 QR을 표시한다. 트론 USDT와 TRX는 동일한 T 주소를 사용한다. 이더리움·맨틀·아발란체는 같은 EVM 주소를 사용하지만 잔액과 거래는 별개다. USDC와 USDT 총잔액은 지원 네트워크별 잔액을 합산하며, 송금은 선택한 네트워크의 실제 잔액으로만 진행한다.

송금은 붙여넣기, 카메라 QR, 앨범 QR을 지원한다. 여러 QR이 있으면 선택한다. 네트워크를 구분할 수 없는 EVM 주소는 사용자가 직접 네트워크를 선택한다. 수수료 확인 뒤 기기 본인 인증으로 서명한다. 최근 전파된 송금 주소를 다시 사용하거나, 네트워크와 함께 이름 주소록에 저장·편집·삭제할 수 있다.

## 거래 처리

- 키는 기존 기기의 Keychain에 보관한다. 온라인 기기에서 서명하는 비수탁 핫월렛이다.
- 수량 입력과 서명은 정수 단위를 사용한다. 잔액 화면의 기존 Solana/BTC/Cardano 조회는 표시용 Double 값을 유지한다.
- 확정 전에는 거래 해시와 동일한 서명 요청을 저장하고 재전파한다. 새 거래를 자동으로 만들어 보내지 않는다.
- Tron/Solana/Cardano의 실제 거래 유효 기간을 기록하며, 네트워크의 확정 상태가 유효 기간을 지났고 거래가 없을 때 만료 처리한다. 서버 장애는 실패로 간주하지 않는다.
- Bitcoin은 이전 거래 원문에서 txid·소유 출력·수량을 확인한다. Cardano는 CBOR 원문 해시, ADA·토큰 입력 및 서명 후 수량 보존을 확인한다.
- Tron은 현재 활성화된 송금자·수신자만 전송한다. 계정이 활성화되지 않았으면 먼저 TRX 입금이 필요하다는 안내를 표시한다.
- Solana는 서명 요청 사전 검사 후 기록·전파한다. Cardano NIGHT에는 최소 ADA 출력 금액이 함께 전송된다.
- 모든 네트워크의 송금 해시·상태를 추적한다. Tron USDT는 최근 확정 수신 거래 최대 50건도 가져온다. 다른 네트워크의 전체 과거 수신 내역 인덱싱은 포함하지 않는다.
- 거래소 입금 대기는 선택한 네트워크의 잔액 증가를 추적한다. 이것은 출금 거래의 독립적인 체인 증명과 동일하지 않다.

## 검증과 실제 사용 한계

Swift 단위 실행 검사, 기존 회귀 검사, iOS 시뮬레이터 빌드 및 공개 테스트 벡터 진단을 사용했다. 검사 결과는 실행 ledger에 기록한다. 사용자 복구 문구를 읽거나 사용자 자금으로 시험 전송하지 않았다. 테스트넷·메인넷의 실제 송금 성공은 아직 검증하지 않았다. 실제 입금과 송금은 기기에 설치한 뒤 소액으로 확인해야 한다.

기기 설치: `ios/Ouryn.xcodeproj`를 Xcode에서 열고 Ouryn 스킴과 연결된 iPhone을 선택한 뒤 실행한다. 기존 앱/Keychain을 지우거나 새 지갑을 만들 필요가 없다. 앱의 복구 문구 백업은 사용자가 직접 확인한다.

## 공개 데이터 의존성

[TronGrid](https://developers.tron.network/reference/account-gettransactionstrc20), [Solana RPC](https://solana.com/docs/rpc), [Koios](https://www.koios.rest/guide/introduction.html), [mempool API](https://mempool.space/docs/api/rest), 네트워크별 EVM RPC를 이용한다. API 장애·사용량 제한 시 마지막 확인 잔액을 유지한다. 서버가 체인 데이터를 제공하므로 자체 풀 노드 수준의 독립적인 체인 검증은 제공하지 않는다.
