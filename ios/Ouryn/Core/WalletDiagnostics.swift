#if DEBUG
import SwiftUI
import WalletCore

struct WalletDiagnosticsView: View {
 @State private var report = "검사 중"
 var body: some View {
  ScrollView { Text(report).padding(24).textSelection(.enabled) }.task {
   var lines = [String]()
   func check(_ value:Bool,_ name:String) { lines.append((value ? "PASS " : "FAIL ") + name) }
   check(WalletKeys.allPassed,"public derivation vectors all seven networks")
   let wallet = HDWallet(mnemonic:"abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",passphrase:"")!
   let addresses:[WalletNetwork:String] = [.tron:wallet.getAddressForCoin(coin:.tron),.solana:wallet.getAddressDerivation(coin:.solana,derivation:.solanaSolana),.ethereum:wallet.getAddressForCoin(coin:.ethereum),.mantle:wallet.getAddressForCoin(coin:.ethereum),.avalanche:wallet.getAddressForCoin(coin:.ethereum),.bitcoin:wallet.getAddressDerivation(coin:.bitcoin,derivation:.bitcoinSegwit),.cardano:wallet.getAddressForCoin(coin:.cardano)]
   for (network,address) in addresses {
    check(WalletKeys.valid(address,network:network),network.rawValue + " address validation")
    if let image = AddressQR.image(address), let data = image.pngData() {
     check(readQRCodes(fromImageData:data) == [address],network.rawValue + " QR roundtrip")
    } else { check(false,network.rawValue + " QR generation") }
   }
   check(!WalletKeys.valid("TLWEciM1CjP5fJqM2r9wymAidkkYtTU5k4",network:.tron),"Tron checksum rejection")
   check(parsePay(addresses[.tron]!)?.network == "트론","Tron raw address parser")
   check(parsePay(addresses[.ethereum]!)?.network == nil,"EVM ambiguity retained")
   check(parsePay("solana:" + addresses[.ethereum]!) == nil,"Solana URI wrong-chain rejection")
   check(parsePay("ouryn:" + addresses[.solana]! + "?a=12&t=t")?.asset == "usdt","USDT amount request retained")
   var legacy = AppState(); legacy.wallet.circle = 100
   do {
    let data = try JSONEncoder().encode(legacy)
    var object = try JSONSerialization.jsonObject(with:data) as! [String:Any]
    object.removeValue(forKey:"networkBalances"); object.removeValue(forKey:"savedRecipients")
    let restored = try JSONDecoder().decode(AppState.self,from:JSONSerialization.data(withJSONObject:object))
    check(restored.wallet.circle == 100 && restored.networkBalances == nil,"legacy state decoding")
   } catch { check(false,"legacy state decoding") }
   // Published Wallet Core Tron transfer signing vector; no user key is read.
   let input = TronSigningInput.with {
    $0.privateKey = Data(hexString:"ba005cd605d8a02e3d5dfd04234cef3a3ee4f76bfbad2722d1fb5af8e12e6764")!
    $0.transaction = TronTransaction.with {
     $0.timestamp = 1539295479000; $0.expiration = 1539331479000
     $0.transfer = TronTransferContract.with { $0.ownerAddress = "TJRyWwFs9wTFGZg3JbrVriFbNfCug5tDeC"; $0.toAddress = "THTR75o8xXAgCTQqpiot2AFRAjvW1tSbVV"; $0.amount = 2000000 }
     $0.blockHeader = TronBlockHeader.with {
      $0.timestamp = 1539295479000; $0.number = 3111739; $0.version = 3
      $0.txTrieRoot = Data(hexString:"64288c2db0641316762a99dbb02ef7c90f968b60f9f2e410835980614332f86d")!
      $0.parentHash = Data(hexString:"00000000002f7b3af4f5f8b9e23a30c530f719f165b742e7358536b280eead2d")!
      $0.witnessAddress = Data(hexString:"415863f6091b8e71766da808b1dd3159790f61de7d")!
     }
    }
   }
   let output:TronSigningOutput = AnySigner.sign(input:input,coin:.tron)
   check(output.error == .ok && output.id.hexString == "dc6f6d9325ee44ab3c00528472be16e1572ab076aa161ccd12515029869d0451","published Tron signing vector")
   let ethereum = EthereumSigningInput.with {
    $0.chainID = Data([1]); $0.nonce = Data([9]); $0.gasPrice = Data(hexString:"04a817c800")!; $0.gasLimit = Data(hexString:"5208")!
    $0.toAddress = "0x3535353535353535353535353535353535353535"
    $0.privateKey = Data(repeating:0x46,count:32)
    $0.transaction = EthereumTransaction.with { $0.transfer = EthereumTransaction.Transfer.with { $0.amount = Data(hexString:"0de0b6b3a7640000")! } }
   }
   let ethOutput:EthereumSigningOutput = AnySigner.sign(input:ethereum,coin:.ethereum)
   check(ethOutput.error == .ok && ethOutput.encoded.hexString == "f86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83","published Ethereum EIP155 signing vector")
   let solana = SolanaSigningInput.with {
    $0.privateKey = Base58.decodeNoCheck(string:"A7psj2GW7ZMdY4E5hJq14KMeYg7HFjULSsWSrTXZLvYr")!
    $0.recentBlockhash = "11111111111111111111111111111111"
    $0.transferTransaction = SolanaTransfer.with { $0.recipient = "EN2sCsJ1WDV8UFqsiTXHcUPUxQ4juE71eCknHYYMifkd"; $0.value = 42 }
   }
   let solOutput:SolanaSigningOutput = AnySigner.sign(input:solana,coin:.solana)
   check(solOutput.error == .ok && solOutput.encoded == "3p2kzZ1DvquqC6LApPuxpTg5CCDVPqJFokGSnGhnBHrta4uq7S2EyehV1XNUVXp51D69GxGzQZUjikfDzbWBG2aFtG3gHT1QfLzyFKHM4HQtMQMNXqay1NAeiiYZjNhx9UvMX4uAQZ4Q6rx6m2AYfQ7aoMUrejq298q1wBFdtS9XVB5QTiStnzC7zs97FUEK2T4XapjF1519EyFBViTfHpGpnf5bfizDzsW9kYUtRDW1UC2LgHr7npgq5W9TBmHf9hSmRgM9XXucjXLqubNWE7HUMhbKjuBqkirRM","published Solana signing vector")
   do {
    let evidence = try CardanoEvidence.parse(Data(hexString:"83a40082825820554f2fd942a23d06835d26bbd78f0106fa94c8a551114a0bef81927f66467af000825820f074134aabbfb13b8aec7cf5465b1e5a862bde5cb88532cc7e64619179b3e76701018282583901558dd902616f5cd01edcc62870cb4748c45403f1228218bee5b628b526f0ca9e7a2c04d548fbd6ce86f358be139fe680652536437d1d6fd51a006acfc082583901df58ee97ce7a46cd8bdeec4e5f3a03297eb197825ed5681191110804df22424b6880b39e4bac8c58de9fe6d23d79aaf44756389d827aa09b1a000ca96c021a000298d4031a032dcd55a100818258206d8a0b425bd2ec9692af39b1c0cf0e51caa07a603550e22f54091e872c7df29058407cf591599852b5f5e007fdc241062405c47e519266c0d884b0767c1d4f5eacce00db035998e53ed10ca4ba5ce4aac8693798089717ce6cf4415f345cc764200ef6")!)
    check(Hash.blake2b(data:evidence.body,size:32).hexString == "9b5b15e133cd73ccaa85307d2986aebc846505118a2eb4e6111e6b4b67d1f389","published Cardano CBOR transaction ID")
    let recipient = "addr1q92cmkgzv9h4e5q7mnrzsuxtgayvg4qr7y3gyx97ukmz3dfx7r9fu73vqn25377ke6r0xk97zw07dqr9y5myxlgadl2s0dgke5"
    check(evidence.outputs[0].address == AnyAddress(string:recipient,coin:.cardano)?.data && evidence.outputs[0].coin == 7000000,"Cardano raw output address and quantity")
    check(evidence.outputs.reduce(UInt64(0)) { $0 + $1.coin } + (evidence.fee ?? 0) == 8000000,"Cardano value conservation")
   } catch { check(false,"Cardano CBOR transaction evidence") }
   if CommandLine.arguments.contains("--network-diagnostics") {
    let health = await withTaskGroup(of:String.self,returning:[String].self) { group in
     for network in WalletNetwork.allCases {
      group.addTask {
       do {
        switch network {
        case .ethereum,.mantle,.avalanche:
         guard let id = ExactAmount.hexDecimal(try await MultiChainAPI.rpc(network,"eth_chainId",[])), id == Decimal(network.chainID!) else { throw MultiChainAPI.APIError.mismatch }
        case .solana:
         guard try await SolanaTransferEngine.rpc("getGenesisHash",[]) as? String == "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d" else { throw MultiChainAPI.APIError.mismatch }
        case .tron:
         let block = try await MultiChainAPI.request(TronTransfer.base + "/wallet/getnowblock",body:[:])
         guard block["blockID"] != nil else { throw MultiChainAPI.APIError.invalid }
        case .bitcoin:
         guard String(data:try await BitcoinTransfer.get("/block-height/0"),encoding:.utf8) == "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f" else { throw MultiChainAPI.APIError.mismatch }
        case .cardano:
         guard let tip = try await CardanoTransfer.query("/tip").first, let epoch = tip["epoch_no"] as? Int else { throw MultiChainAPI.APIError.invalid }
         let params = try await CardanoTransfer.query("/epoch_params?_epoch_no=\(epoch)")
         guard let p = params.first, p["coins_per_utxo_size"] as? String != nil else { throw MultiChainAPI.APIError.invalid }
        }
        return "PASS " + network.rawValue + " public mainnet API"
       } catch { return "FAIL " + network.rawValue + " public mainnet API: " + error.localizedDescription }
      }
     }
     var lines:[String] = []; for await result in group { lines.append(result) }; return lines.sorted()
    }
    lines.append(contentsOf:health)
   }
   report = lines.joined(separator:"\n")
   try? report.write(to:FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("multichain-diagnostics.txt"),atomically:true,encoding:.utf8)
  }
 }
}
#endif
