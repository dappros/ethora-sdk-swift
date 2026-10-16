//
//  E2EEKnownAnswerTests.swift
//  XMPPChatCoreTests
//
//  Byte-for-byte checks of the OMEMO port against vectors generated from the web
//  implementation (see E2EEVectorsFixture.swift).
//

import XCTest
@testable import XMPPChatCore

final class E2EEKnownAnswerTests: XCTestCase {

    private var v: [String: Any]!

    // Fixed inputs used by the generator (ethora-chat-component harness).
    private func seq(_ start: Int, _ n: Int) -> Data {
        Data((0..<n).map { UInt8((start + $0) & 0xff) })
    }

    private func hex(_ data: Data) -> String { E2EECrypto.toHex(data) }

    private func str(_ key: String) -> String {
        guard let value = v[key] as? String else {
            XCTFail("missing vector \(key)")
            return ""
        }
        return value
    }

    private func dict(_ key: String) -> [String: Any] {
        guard let value = v[key] as? [String: Any] else {
            XCTFail("missing vector \(key)")
            return [:]
        }
        return value
    }

    private func bytesFromHex(_ text: String) -> Data {
        var out = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            out.append(UInt8(text[index..<next], radix: 16)!)
            index = next
        }
        return out
    }

    override func setUpWithError() throws {
        v = try JSONSerialization.jsonObject(with: Data(e2eeVectorsJSON.utf8)) as? [String: Any]
    }

    // MARK: - Primitives

    func testHKDFOutputsMatchWeb() {
        XCTAssertEqual(hex(E2EECrypto.hkdfSha256(ikm: seq(1, 32), salt: nil, info: "OMEMO Payload", length: 80)), str("hkdf_payload"))
        XCTAssertEqual(hex(E2EECrypto.hkdfSha256(ikm: seq(9, 32), salt: nil, info: "OMEMO Message Key Material", length: 80)), str("hkdf_mk"))
        XCTAssertEqual(hex(E2EECrypto.hkdfSha256(ikm: seq(3, 128), salt: nil, info: "OMEMO X3DH", length: 32)), str("hkdf_x3dh"))
        XCTAssertEqual(hex(E2EECrypto.hkdfSha256(ikm: seq(5, 32), salt: seq(40, 32), info: "OMEMO Root Chain", length: 64)), str("hkdf_root"))
    }

    func testHMACMatchesWeb() {
        XCTAssertEqual(hex(E2EECrypto.hmacSha256(key: seq(20, 32), data: seq(60, 50))), str("hmac"))
    }

    func testAESCBCMatchesWeb() throws {
        let cases = v["aes"] as? [[String: Any]] ?? []
        XCTAssertEqual(cases.count, 4)
        for item in cases {
            let n = item["n"] as? Int ?? -1
            let ct = try E2EECrypto.aesEncrypt(key: seq(70, 32), iv: seq(90, 16), data: seq(120, n))
            XCTAssertEqual(hex(ct), item["ct"] as? String, "plaintext length \(n)")
            let pt = try E2EECrypto.aesDecrypt(key: seq(70, 32), iv: seq(90, 16), data: ct)
            XCTAssertEqual(pt, seq(120, n))
        }
    }

    func testPayloadEncryptionMatchesWeb() throws {
        let payload = dict("payload")
        let plain = bytesFromHex(payload["plaintext"] as! String)
        let sealed = try E2EERatchet.encryptPayload(plain, key: seq(200, 32))
        XCTAssertEqual(hex(sealed.keyMaterial), payload["keyMaterial"] as? String)
        XCTAssertEqual(hex(sealed.payload), payload["payload"] as? String)
        XCTAssertEqual(try E2EERatchet.decryptPayload(keyMaterial: sealed.keyMaterial, payload: sealed.payload), plain)
    }

    // MARK: - Protobuf

    func testProtobufEncodingMatchesWeb() {
        let message = E2EEOmemoMessage(n: 300, pn: 70000, dhPub: seq(1, 32), ciphertext: seq(50, 20))
        XCTAssertEqual(hex(E2EEProtobuf.encodeMessage(message)), str("proto_message"))
        XCTAssertEqual(hex(E2EEProtobuf.encodeMessage(E2EEOmemoMessage(n: 0, pn: 0, dhPub: seq(7, 32), ciphertext: nil))), str("proto_message_nocipher"))
        XCTAssertEqual(hex(E2EEProtobuf.encodeAuthenticated(E2EEAuthenticatedMessage(mac: seq(1, 16), message: seq(2, 40)))), str("proto_auth"))
    }

    func testProtobufDecodesWebOutput() throws {
        let decoded = try E2EEProtobuf.decodeMessage(bytesFromHex(str("proto_message")))
        XCTAssertEqual(decoded.n, 300)
        XCTAssertEqual(decoded.pn, 70000)
        XCTAssertEqual(decoded.dhPub, seq(1, 32))
        XCTAssertEqual(decoded.ciphertext, seq(50, 20))
    }

    func testProtobufRejectsTruncatedInput() {
        XCTAssertThrowsError(try E2EEProtobuf.decodeMessage(Data([0x08])))
        XCTAssertThrowsError(try E2EEProtobuf.decodeMessage(Data([0x08, 0x01, 0x10, 0x00])))
    }

    // MARK: - Identity and X3DH

    func testEd25519ToX25519MapMatchesWeb() throws {
        let x = dict("x3dh")
        XCTAssertEqual(hex(E2EECrypto.identityDhPublic(identityPub: bytesFromHex(x["bobIkPub"] as! String)) ?? Data()), x["ed2x_bobPub"] as? String)
        XCTAssertEqual(hex(E2EECrypto.identityDhPrivate(seed: seq(101, 32))), x["ed2x_bobSeedPriv"] as? String)
    }

    func testIdentityAndSignatureMatchWeb() throws {
        let x = dict("x3dh")
        XCTAssertEqual(hex(try E2EECrypto.identityPublicKey(seed: seq(101, 32))), x["bobIkPub"] as? String)
        XCTAssertEqual(hex(try E2EECrypto.identityPublicKey(seed: seq(1, 32))), x["aliceIkPub"] as? String)
        let spkPub = bytesFromHex(x["spk"] as! String)
        let sig = bytesFromHex(x["spkSig"] as! String)
        let bob = E2EEIdentityKey(seed: seq(101, 32), pub: bytesFromHex(x["bobIkPub"] as! String))
        XCTAssertEqual(hex(try E2EECrypto.sign(identity: bob, message: spkPub)), x["spkSig"] as? String)
        XCTAssertTrue(E2EECrypto.verify(signature: sig, message: spkPub, identityPub: bob.pub))
    }

    func testX25519PublicKeysMatchWeb() throws {
        let x = dict("x3dh")
        XCTAssertEqual(hex(try E2EECrypto.x25519PublicKey(priv: seq(151, 32))), x["spk"] as? String)
        XCTAssertEqual(hex(try E2EECrypto.x25519PublicKey(priv: seq(191, 32))), x["ekPub"] as? String)
        XCTAssertEqual(hex(try E2EECrypto.x25519PublicKey(priv: seq(211, 32))), x["dhsPub"] as? String)
    }

    // MARK: - Ratchet

    private func bobBundle() throws -> E2EEBundle {
        let x = dict("x3dh")
        return E2EEBundle(
            ik: bytesFromHex(x["bobIkPub"] as! String),
            spkId: 1,
            spk: bytesFromHex(x["spk"] as! String),
            spkSignature: bytesFromHex(x["spkSig"] as! String),
            pkId: 7,
            pk: bytesFromHex(x["pk"] as! String)
        )
    }

    private func aliceIdentity() -> E2EEIdentityKey {
        E2EEIdentityKey(seed: seq(1, 32), pub: bytesFromHex(dict("x3dh")["aliceIkPub"] as! String))
    }

    func testInitialSessionAndSendChainMatchWeb() throws {
        let x = dict("x3dh")
        let ek = E2EEKeyPair(priv: seq(191, 32), pub: bytesFromHex(x["ekPub"] as! String))
        let dhs = E2EEKeyPair(priv: seq(211, 32), pub: bytesFromHex(x["dhsPub"] as! String))
        var alice = try E2EERatchet.initiateSession(own: aliceIdentity(), bundle: try bobBundle(), ek: ek, dhs: dhs)
        XCTAssertEqual(hex(alice.rk), x["initRk"] as? String)
        XCTAssertEqual(hex(alice.cks ?? Data()), x["initCks"] as? String)
        XCTAssertEqual(hex(alice.ad), x["initAd"] as? String)
        XCTAssertEqual(alice.pendingKex, E2EEPendingKex(pkId: 7, spkId: 1, ek: ek.pub))

        let plains = (v["ratchet_plains"] as! [String]).map(bytesFromHex)
        let expected = v["ratchet_alice_msgs"] as! [String]
        for (index, plain) in plains.enumerated() {
            let (next, data) = try E2EERatchet.ratchetEncrypt(alice, plaintext: plain)
            alice = next
            XCTAssertEqual(hex(data), expected[index], "message \(index + 1)")
        }
        XCTAssertEqual(alice.ns, v["ratchet_alice_final_ns"] as? Int)
    }

    func testBobDecryptsOutOfOrderAndRepliesLikeWeb() throws {
        let x = dict("x3dh")
        let ekPub = bytesFromHex(x["ekPub"] as! String)
        let spk = E2EEKeyPair(priv: seq(151, 32), pub: bytesFromHex(x["spk"] as! String))
        let pk = E2EEKeyPair(priv: seq(171, 32), pub: bytesFromHex(x["pk"] as! String))
        let bob0 = try E2EERatchet.acceptSession(
            own: E2EEIdentityKey(seed: seq(101, 32), pub: bytesFromHex(x["bobIkPub"] as! String)),
            spk: spk, pk: pk, peerIk: aliceIdentity().pub, ek: ekPub
        )
        XCTAssertEqual(hex(bob0.rk), x["bobRk"] as? String)
        XCTAssertEqual(hex(bob0.ad), x["bobAd"] as? String)

        let sent = (v["ratchet_alice_msgs"] as! [String]).map(bytesFromHex)
        let plains = (v["ratchet_plains"] as! [String]).map(bytesFromHex)
        var bob = bob0
        // The first decrypt performs Bob's DH ratchet step; the generator pinned that key.
        let pinned = E2EEKeyPair(priv: seq(231, 32), pub: try E2EECrypto.x25519PublicKey(priv: seq(231, 32)))
        var calls = 0
        let keyGen: () -> E2EEKeyPair = { calls += 1; return pinned }

        var out = Data()
        (bob, out) = try E2EERatchet.ratchetDecrypt(bob, data: sent[2], keyGenerator: keyGen)
        XCTAssertEqual(out, plains[2])
        (bob, out) = try E2EERatchet.ratchetDecrypt(bob, data: sent[0], keyGenerator: keyGen)
        XCTAssertEqual(out, plains[0])
        (bob, out) = try E2EERatchet.ratchetDecrypt(bob, data: sent[1], keyGenerator: keyGen)
        XCTAssertEqual(out, plains[1])
        XCTAssertEqual(calls, 1, "one DH ratchet step for the whole burst")

        let (_, reply) = try E2EERatchet.ratchetEncrypt(bob, plaintext: bytesFromHex(str("ratchet_bob_reply_plain")))
        XCTAssertEqual(hex(reply), str("ratchet_bob_reply"))
    }

    func testKeyExchangeWrappedMessageMatchesWeb() throws {
        let x = dict("x3dh")
        let sent0 = bytesFromHex((v["ratchet_alice_msgs"] as! [String])[0])
        let kex = E2EEKeyExchangeMessage(
            pkId: 7, spkId: 1,
            ik: bytesFromHex(x["aliceIkPub"] as! String),
            ek: bytesFromHex(x["ekPub"] as! String),
            message: sent0
        )
        XCTAssertEqual(hex(E2EEProtobuf.encodeKeyExchange(kex)), str("kex_wrapped_m1"))
        XCTAssertEqual(try E2EEProtobuf.decodeKeyExchange(bytesFromHex(str("kex_wrapped_m1"))), kex)
    }

    // MARK: - File envelope

    func testFileEnvelopeMatchesWeb() throws {
        let meta = E2EEFileMeta(mimetype: "application/pdf", originalname: "Contract ü.pdf", size: 5)
        XCTAssertEqual(hex(E2EEFileEnvelope.encode(meta: meta, bytes: seq(1, 5))), str("file_envelope"))
        let decoded = try E2EEFileEnvelope.decode(bytesFromHex(str("file_envelope")))
        XCTAssertEqual(decoded.meta, meta)
        XCTAssertEqual(decoded.bytes, seq(1, 5))
    }

    func testSealedFileMatchesWebAndOpens() throws {
        let sealedVector = dict("file_sealed")
        let sealed = try E2EEFileEnvelope.sealForUpload(
            bytes: seq(1, 5),
            mimetype: "application/pdf",
            originalName: "Contract ü.pdf",
            key: seq(240, 32),
            filenameBytes: seq(10, 16)
        )
        XCTAssertEqual(sealed.keyMaterial, sealedVector["keyMaterial"] as? String)
        XCTAssertEqual(hex(sealed.ciphertext), sealedVector["ciphertext"] as? String)
        XCTAssertEqual(sealed.filename, sealedVector["filename"] as? String)

        let opened = try E2EEFileEnvelope.open(ciphertext: bytesFromHex(sealedVector["ciphertext"] as! String), keyMaterial: sealedVector["keyMaterial"] as! String)
        XCTAssertEqual(opened.meta.originalname, "Contract ü.pdf")
        XCTAssertEqual(opened.bytes, seq(1, 5))
    }

    func testSealedMediaPayloadParsing() {
        let parsed = E2EEFileEnvelope.parseSealedMediaPayload(#"{"v":1,"keys":["abc=="],"caption":"look","captionMentions":[]}"#)
        XCTAssertEqual(parsed?.keys, ["abc=="])
        XCTAssertEqual(parsed?.caption, "look")
        XCTAssertNil(parsed?.captionMentions)
        XCTAssertNil(E2EEFileEnvelope.parseSealedMediaPayload("media"))
        XCTAssertNil(E2EEFileEnvelope.parseSealedMediaPayload(#"{"v":true,"keys":["a"]}"#))
        XCTAssertNil(E2EEFileEnvelope.parseSealedMediaPayload(#"{"v":1,"keys":[]}"#))
    }
}
