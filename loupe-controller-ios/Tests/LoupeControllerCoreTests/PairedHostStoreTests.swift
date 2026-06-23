// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PairedHostStoreTests.swift
// Sprint 17 (2026-06-23): unit tests for the iOS-side
// persistent-pairing store (the controller's view of the
// paired hosts).

import XCTest
import CryptoKit
@testable import LoupeCore

final class PairedHostStoreTests: XCTestCase {

    private var tempURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoupeTest-PairedHostStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempURL = dir.appendingPathComponent("paired-hosts.json")
    }

    override func tearDownWithError() throws {
        if let dir = tempURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func testEmptyStoreReturnsEmptyList() throws {
        let store = PairedHostStore(fileURL: tempURL)
        XCTAssertEqual(try store.listHosts().count, 0)
    }

    func testAddHostAndList() throws {
        let store = PairedHostStore(fileURL: tempURL)
        let host = makeHost(name: "Miggu's Mac Studio")
        try store.addHost(host)
        let all = try store.listHosts()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, host.id)
        XCTAssertEqual(all[0].displayName, "Miggu's Mac Studio")
    }

    func testDuplicatePublicKeyRejected() throws {
        let store = PairedHostStore(fileURL: tempURL)
        let key = Data(repeating: 0x42, count: 32)
        try store.addHost(makeHost(name: "First", publicKey: key))
        XCTAssertThrowsError(try store.addHost(makeHost(name: "Second", publicKey: key))) { err in
            XCTAssertEqual(err as? PairedHostStoreError, .duplicatePublicKey)
        }
    }

    func testRevokeHostMarksIsRevoked() throws {
        let store = PairedHostStore(fileURL: tempURL)
        let host = makeHost(name: "Miggu's Mac Studio")
        try store.addHost(host)
        try store.revokeHost(id: host.id)
        let reloaded = try store.host(for: host.id)
        XCTAssertEqual(reloaded?.isRevoked, true)
        XCTAssertEqual(try store.listHosts().count, 1)
    }

    func testPersistenceAcrossInstances() throws {
        let store1 = PairedHostStore(fileURL: tempURL)
        let host = makeHost(name: "Miggu's Mac Studio")
        try store1.addHost(host)

        let store2 = PairedHostStore(fileURL: tempURL)
        XCTAssertEqual(try store2.listHosts().count, 1)
        XCTAssertEqual(try store2.host(for: host.id)?.id, host.id)
    }

    func testFilePermissionsAre0600() throws {
        let store = PairedHostStore(fileURL: tempURL)
        try store.addHost(makeHost(name: "Miggu's Mac Studio"))
        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(perms & 0o777, 0o600)
    }

    // MARK: - Helpers

    private func makeHost(name: String, publicKey: Data? = nil) -> PairedHost {
        let pubKey = publicKey ?? Data((0..<32).map { UInt8($0) })
        let sessionKey = Data((0..<32).map { UInt8($0 + 100) })
        return PairedHost(
            displayName: name,
            hostPublicKey: pubKey,
            sessionKey: sessionKey,
            signalingURL: "wss://signaling.theloupe.team"
        )
    }
}
