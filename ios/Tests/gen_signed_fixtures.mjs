// check_signed.swift 고정값 만들기 — Wallet Core를 올릴 때 다시 돌려서 결과가 같은지 확인
// 빈 폴더에서: npm i @trustwallet/wallet-core@<앱과 같은 버전> && node gen_signed_fixtures.mjs > signed.json
// 공개 테스트 문구("abandon … about")만 씀. 실제 지갑 문구를 넣지 말 것.
import { initWasm, TW } from "@trustwallet/wallet-core";
const core = await initWasm();
const { AnySigner, CoinType, HexCoding, HDWallet, Base58, SolanaAddress } = core;
const hex = (u) => Buffer.from(u).toString("hex");
const big = (n) => { let h = BigInt(n).toString(16); if (h.length%2) h="0"+h; return Buffer.from(h,"hex"); };
const w = HDWallet.createWithMnemonic("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about","");
const ethKey = w.getKey(CoinType.ethereum, "m/44'/60'/0'/0/0").data();
const ethAddr = w.getAddressForCoin(CoinType.ethereum);
function evm(chain, nonce, price, limit, to, tx) {
  const input = TW.Ethereum.Proto.SigningInput.create({ chainId: big(chain), nonce: big(nonce), gasPrice: big(price), gasLimit: big(limit), toAddress: to, privateKey: ethKey, transaction: tx });
  const out = TW.Ethereum.Proto.SigningOutput.decode(AnySigner.sign(TW.Ethereum.Proto.SigningInput.encode(input).finish(), CoinType.ethereum));
  return { error: out.error, encoded: hex(out.encoded) };
}
const r = {};
r.ethOwner = ethAddr;
r.evmNative = { chain:1, nonce:"9", gasPrice:"20000000000", gasLimit:"25200", to:"0x3535353535353535353535353535353535353535", amount:"1000000000000000000",
  ...evm(1, 9, 20000000000n, 25200, "0x3535353535353535353535353535353535353535", { transfer: { amount: big(10n**18n) } }) };
r.evmToken = { chain:43114, nonce:"0", gasPrice:"25000000000", gasLimit:"78000", contract:"0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7", to:"0x5322b34c88ed0691971bf52a7047448f0f4efc84", amount:"2500000",
  ...evm(43114, 0, 25000000000n, 78000, "0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7", { erc20Transfer: { to: "0x5322b34c88ed0691971bf52a7047448f0f4efc84", amount: big(2500000) } }) };
r.evmZeroNonce = evm(5000, 0, 1n, 21000, "0x3535353535353535353535353535353535353535", { transfer: { amount: big(1) } });
// Solana
const solKey = w.getKey(CoinType.solana, "m/44'/501'/0'/0'").data();
const solOwner = CoinType ? core.AnyAddress.createWithPublicKey(w.getKey(CoinType.solana,"m/44'/501'/0'/0'").getPublicKeyEd25519(), CoinType.solana).description() : "";
const recipient = "EN2sCsJ1WDV8UFqsiTXHcUPUxQ4juE71eCknHYYMifkd";
const blockhash = "11111111111111111111111111111111";
const realHash = "5ZRWcVjXBTTGy8qMwHiPpLpNsg8vXhWjf5mpwpJ3yPWa";
const USDC = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";
const ata = (o,m) => SolanaAddress.createWithString(o).defaultTokenAddress(m);
function sol(tx){
  const input = TW.Solana.Proto.SigningInput.create({ privateKey: solKey, recentBlockhash: realHash, ...tx });
  const out = TW.Solana.Proto.SigningOutput.decode(AnySigner.sign(TW.Solana.Proto.SigningInput.encode(input).finish(), CoinType.solana));
  return { error: out.error, errorMessage: out.errorMessage, encoded: out.encoded };
}
r.solOwner = solOwner; r.solRecipient = recipient; r.blockhash = realHash; r.usdc = USDC;
r.senderToken = ata(solOwner, USDC); r.recipientToken = ata(recipient, USDC);
r.solNative = { amount:"1000000", ...sol({ transferTransaction: { recipient, value: 1000000 } }) };
r.solToken = { amount:"2500000", ...sol({ tokenTransferTransaction: { tokenMintAddress: USDC, senderTokenAddress: r.senderToken, recipientTokenAddress: r.recipientToken, amount: 2500000, decimals: 6 } }) };
r.solCreate = { amount:"2500000", ...sol({ createAndTransferTokenTransaction: { recipientMainAddress: recipient, tokenMintAddress: USDC, senderTokenAddress: r.senderToken, recipientTokenAddress: r.recipientToken, amount: 2500000, decimals: 6 } }) };
console.log(JSON.stringify(r,null,1));
