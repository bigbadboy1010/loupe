// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PairedDeviceStoreTests.swift
// Sprint 17 (2026-06-23): unit tests for the host-side
// persistent-pairing store. These tests are intentionally
// self-contained (no test fixtures, no shared state) so they
// pass in CI without Docker or a running relay.

import XCTest
import CryptoKit
@testable import LoupeHostCore

final class PairedDeviceStoreTests: XCTestCase {

    private var tempURL: URL!

    override func setUpWithError() throws {
        // Use a unique file per test so parallel runs don't collide.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoupeTest-PairedDeviceStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempURL = dir.appendingPathComponent("paired-devices.json")
    }

    override func tearDownWithError() throws {
        if let dir = tempURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func testEmptyStoreReturnsEmptyList() throws {
        let store = PairedDeviceStore(fileURL: tempURL)
        XCTAssertEqual(try store.listDevices().count, 0)
    }

    func testAddDeviceAndList() throws {
        let store = PairedDeviceStore(fileURL: tempURL)
        let device = makeDevice(name: "Miggu's iPhone")
        try store.addDevice(device)
        let all = try store.listDevices()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, device.id)
        XCTAssertEqual(all[0].displayName, "Miggu's iPhone")
    }

    func testDuplicatePublicKeyRejected() throws {
        let store = PairedDeviceStore(fileURL: tempURL)
        let key = Data(repeating: 0x42, count: 32)
        try store.addDevice(makeDevice(name: "First", publicKey: key))
        XCTAssertThrowsError(try store.addDevice(makeDevice(name: "Second", publicKey: key))) { err in
            XCTAssertEqual(err as? PairedDeviceStoreError, .duplicatePublicKey)
        }
    }

    func testUpdateDeviceTouchesLastSeen() throws {
        let store = PairedDeviceStore(fileURL: tempURL)
        var device = makeDevice(name: "Miggu's iPhone")
        try store.addDevice(device)
        let original = device.lastSeen
        device.lastSeen = original.addingTimeInterval(3600)
        try store.updateDevice(device)
        let reloaded = try store.device(for: device.id)
        XCTAssertEqual(reloaded?.lastSeen, device.lastSeen)
    }

    func testRevokeDeviceMarksIsRevoked() throws {
        let store = PairedDeviceStore(fileURL: tempURL)
        let device = makeDevice(name: "Miggu's iPhone")
        try store.addDevice(device)
        try store.revokeDevice(id: device.id)
        let reloaded = try store.device(for: device.id)
        XCTAssertEqual(reloaded?.isRevoked, true)
        // The record stays in the list for audit purposes.
        XCTAssertEqual(try store.listDevices().count, 1)
    }

    func testRevokeUnknownDeviceThrows() throws {
        let store = PairedDeviceStore(fileURL: tempURL)
        XCTAssertThrowsError(try store.revokeDevice(id: UUID())) { err in
            XCTAssertEqual(err as? PairedDeviceStoreError, .deviceNotFound)
        }
    }

    func testFilePermissionsAre0600() throws {
        let store = PairedDeviceStore(fileURL: tempURL)
        try store.addDevice(makeDevice(name: "Miggu's iPhone"))
        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(perms & 0o777, 0o600)
    }

    func testPersistenceAcrossInstances() throws {
        let store1 = PairedDeviceStore(fileURL: tempURL)
        let device = makeDevice(name: "Miggu's iPhone")
        try store1.addDevice(device)

        // New instance reading the same file.
        let store2 = PairedDeviceStore(fileURL: tempURL)
        let all = try store2.listDevices()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, device.id)
    }

    // MARK: - Helpers

    private func makeDevice(name: String, publicKey: Data? = nil) -> PairedDevice {
        let pubKey = publicKey ?? Data((0..<32).map { UInt8($0) })
        let sessionKey = Data((0..<32).map { UInt8($0 + 100) })
        return PairedDevice(
            displayName: name,
            controllerPublicKey: pubKey,
            sessionKey: sessionKey
        )
    }
}
