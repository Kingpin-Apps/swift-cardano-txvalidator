import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

/// Mainnet transactions that carry datums but no redeemers.
///
/// A transaction that only *sends* to a script address attaches the output's
/// datum to the witness set and sets `script_data_hash`, without running any
/// script — so it has no redeemers field at all. The ledger still hashes the
/// empty redeemers map, and these on-chain hashes are the oracle for that:
/// every one of them was accepted by the ledger, so the declared hash is
/// correct by construction and any mismatch is the validator's fault.
@Suite("script_data_hash with datums but no redeemers")
struct ScriptDataHashNoRedeemersTests {

    /// `1a713b94…` — datums as `#6.258` around a definite array.
    static let firstTx = "84a900828258206068b43c2cb93fc7b7d4cb4d1e9c97aef45312ef55bf83c303d4dc8aa33423bf02825820c0a9b22491f0c53631e1c1333a6440bdc751bef800e5bc0851ca0c6194e2047a010184a300581d7153a4b333f278cff12049325a3bd47b236d294112292ae87092b861e001821a003d0900a1581c25c5de5f5b286073c593edfd77b48abc7a48e5a4f3d4cd9d428ff935a144444547411b0002aa1efb94e0000282005820fabc87eee3ab2cb5fb20915d80e54b8edc730f99cc54b2ee0f9c668700da39c7a200583901ffebcc9e31749eb5803e396202d84e3b436ec362463b2fd70fb4c8819086fc9117b2dadb43da1f922c46039a47d51bff09433dcdd18f1cce011a004c4b40a20058390197afdd6c407a490b7ae46e2d1edf1b2c0d2a1f77e320515e52f075d92745904fc43c9a36cc72d7ad454a2153b3a8243fa4d5ab7b13725bd2011a001e8480a20058390197afdd6c407a490b7ae46e2d1edf1b2c0d2a1f77e320515e52f075d92745904fc43c9a36cc72d7ad454a2153b3a8243fa4d5ab7b13725bd201821a010a9a16a1581c25c5de5f5b286073c593edfd77b48abc7a48e5a4f3d4cd9d428ff935a144444547411b000092e6a909065d021a00030ffd031a0bd81a75075820360dded0dc97b71db4f18c3db30dc925293047f9370d96fbc2c8cf5335af4955081a0bd80c650b58203229e2759fbfc00f3a94d5179c4b07ddead1abf0c71d3ee0d22cb5cbb99bdb400e82581c97afdd6c407a490b7ae46e2d1edf1b2c0d2a1f77e320515e52f075d9581c2745904fc43c9a36cc72d7ad454a2153b3a8243fa4d5ab7b13725bd20f01a20082825820ea45f54bf96fb0de1956f79a43c3e9c13c5ab05efd4404729fa55bb166c2548e5840352a169a3a8a87e502c951a44c0ae1d54e9a1bedd35515b4115a8ed026ac2e9c7bcb06586d53ccb32d61f814b26564e8b5bd58cf32556a593bb57c0d6310510b82582046dbdd523ec183b1f34f2827324af35f37a02e60cd6b6ae6a89cbfb6c375d7135840221e07d6cc222bc7d5caac869da47a0644ef988b51df816d61d46013b84ee5982e9353238856e77809aa0353784e43643ec1849c4f8522a972aebd1fa7828a0404d9010281d8799f583897afdd6c407a490b7ae46e2d1edf1b2c0d2a1f77e320515e52f075d92745904fc43c9a36cc72d7ad454a2153b3a8243fa4d5ab7b13725bd2d87d9f1a09d68217fffff5a11902a2a1636d7367826f44657868756e74657220547261646570506172746e6572205645535052694f53"
    static let firstHash = "3229e2759fbfc00f3a94d5179c4b07ddead1abf0c71d3ee0d22cb5cbb99bdb40"

    /// `341b7e56…` — a second, larger transaction of the same shape.
    ///
    /// A third mainnet reproducer, `157e6e6c…`, has its datums as `#6.258`
    /// around an *indefinite* array. It is not exercised here because decoding
    /// it needs the separate tag-258 indefinite-array fix in swift-cardano-core;
    /// its on-chain hash is
    /// `810cc16197b6791d211bc55d36c6ea1c772456473dd7b7e54b1f1fcdfe96269b`.
    static let secondTx = "84a600d901028382582006a40539d900f21d9c3cdb3429468ab285cd218f6443e9aa9c50107f46df2ce103825820204b4ab09d7bac8ba0e6a25185b827a995d6aa9d49645b55a598ca94dffa3bde00825820803f905e09d085644b87d62d1a362a28830f664f2e7dde17a8a17469baa9aad5010184a300581d71c3e28c36c3447315ba5a56f33da6a6ddc1770a876a8d9f0cb3a97c4c011a2973ebc0028201d818590130d8799fd8799f581c1ee35346257cc3977c0fdedd925f37c3db2688eb6c2a9c872619ff93ffd8799fd8799f581c1ee35346257cc3977c0fdedd925f37c3db2688eb6c2a9c872619ff93ffd8799fd8799fd8799f581c07f2a23f223d445581b1654fad2f18e0edade8ae2674fabd2a26ba60ffffffffd87980d8799fd8799f581c1ee35346257cc3977c0fdedd925f37c3db2688eb6c2a9c872619ff93ffd8799fd8799fd8799f581c07f2a23f223d445581b1654fad2f18e0edade8ae2674fabd2a26ba60ffffffffd87980d8799f581cf5808c2c990d86da54bfc97d89cee6efa20cd8461616359478d96b4c58209b65707373c4cec488b16151a64d7102dbae16857c500652b5c513650b8d604effd8799fd87a80d8799f1a2936e2c0ff1a4ef7ce94d87980ff1a001e8480d87a80ff83583911a65ca58a4e9c755fa830173d2a5caed458ac0c73f97db7faae2e7e3b52563c5410bff6a0d43ccebb7c37e1f69f5eb260552521adff33b9c21a2210f70058200f0c992426e4081cc9042d70c3b997b9f0894dbbedc24a3c8f39a1dd66e510fb82583901661ae4b23b24ba9656d78b7637e6a66e889fa788c16c88017e494052c2c5baab297046f996aea6faa54eb92b6005bdb22c8288de08064e371a000f4240825839011ee35346257cc3977c0fdedd925f37c3db2688eb6c2a9c872619ff9307f2a23f223d445581b1654fad2f18e0edade8ae2674fabd2a26ba60821a025e8c70a3581c0691b2fecca1ac4f53cb6dfb00b7013e561d1f34403b957cbb5af1faa1454e494748541a0dc916e1581c2d9db8a89f074aa045eab177f23a3395f62ced8b53499a9e4ad46c80a144464c4f571a00031de1581c5b26e685cc5c9ad630bde3e3cd48c694436671f3d25df53777ca60efa1434e564c1a01540db9021a00033bb1031a0bd813eb0758203b308c148cd78090ef1c8e41e30f288b4c04df1a2296fd1c89b320d120bb49750b58207efc665b22a0a873fb5ede28c1c65bafd18e130ee4fc7bc285ab6055d138b9ffa20081825820d324add912c240f1dcbfa7305771c1c2307c9c205cb8f14c7484fbf15911f7cb5840704ee65b8a40cf928d314bcd09cbdd87797efbd7edb2fe2290fa4e347cbf5734f361c85964c30ea3aa26631456e6e818346f8eb3eef7389c8a4848a37e8ee00604d9010281d8799fd8799fd8799f581c1ee35346257cc3977c0fdedd925f37c3db2688eb6c2a9c872619ff93ffd8799fd8799fd8799f581c07f2a23f223d445581b1654fad2f18e0edade8ae2674fabd2a26ba60ffffffffd8799fd8799f581c1ee35346257cc3977c0fdedd925f37c3db2688eb6c2a9c872619ff93ffd8799fd8799fd8799f581c07f2a23f223d445581b1654fad2f18e0edade8ae2674fabd2a26ba60ffffffffd87a80d8799fd8799f581c533bb94a8850ee3ccbe483106489399112b74c905342cb1792a797a044494e4459ff1a40ce4978ff1a001e84801a001e8480fff5d90103a100a11902a2a1636d7367826643617244654d71537465656c537761703a20312e31382e30"
    static let secondHash = "7efc665b22a0a873fb5ede28c1c65bafd18e130ee4fc7bc285ab6055d138b9ff"

    @Test("the fixtures really do have datums and no redeemers")
    func fixtureShape() throws {
        for hex in [Self.firstTx, Self.secondTx] {
            let tx = try TransactionParser().parse(cborHex: hex)
            #expect(tx.transactionWitnessSet.plutusData != nil)
            #expect(tx.transactionWitnessSet.redeemers == nil)
        }
    }

    @Test("recomputed hash matches the on-chain hash")
    func firstTransaction() throws {
        let tx = try TransactionParser().parse(cborHex: Self.firstTx)
        let computed = try Utils.scriptDataHash(
            witnessSet: tx.transactionWitnessSet,
            protocolParams: try loadProtocolParams(),
            transaction: tx
        )
        #expect(computed.payload.toHex == Self.firstHash)
    }

    @Test("recomputed hash matches the on-chain hash (second transaction)")
    func secondTransaction() throws {
        let tx = try TransactionParser().parse(cborHex: Self.secondTx)
        let computed = try Utils.scriptDataHash(
            witnessSet: tx.transactionWitnessSet,
            protocolParams: try loadProtocolParams(),
            transaction: tx
        )
        #expect(computed.payload.toHex == Self.secondHash)
    }

    @Test("the rule reports no mismatch for either transaction")
    func ruleAcceptsBoth() throws {
        for hex in [Self.firstTx, Self.secondTx] {
            let tx = try TransactionParser().parse(cborHex: hex)
            // Resolve every spending input to a key address. Without this the
            // rule downgrades a mismatch to a warning, which would hide the
            // regression this test is here to catch.
            let context = ValidationContext(
                resolvedInputs: tx.transactionBody.inputs.asArray.map { input in
                    UTxO(
                        input: input,
                        output: TransactionOutput(
                            address: try! Address(
                                paymentPart: .verificationKeyHash(
                                    VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
                                ),
                                network: .mainnet
                            ),
                            amount: Value(coin: 1_000_000_000)
                        )
                    )
                }
            )
            let issues = try ScriptIntegrityRule().validate(
                transaction: tx,
                context: context,
                protocolParams: try loadProtocolParams()
            )
            #expect(!issues.contains { $0.kind == .scriptDataHashMismatch })
            #expect(!issues.contains { $0.kind == .cannotCheckScriptDataHash })
        }
    }
}
