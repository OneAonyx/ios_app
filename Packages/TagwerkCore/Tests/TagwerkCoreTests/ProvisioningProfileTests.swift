import Foundation
import Testing
@testable import TagwerkCore

@Suite("Provisioning-Profil & Signatur")
struct ProvisioningProfileTests {
    /// Baut eine Datei wie `embedded.mobileprovision`: Binärmüll + XML-Plist + Binärmüll.
    private func makeProfileData(
        created: Date,
        expires: Date,
        getTaskAllow: Bool = true,
        allDevices: Bool = false,
        appGroups: [String] = ["group.de.tagwerk.app.ABCDE12345"],
        healthKit: Bool = true
    ) throws -> Data {
        var entitlements: [String: Any] = [
            "application-identifier": "ABCDE12345.de.tagwerk.app.ABCDE12345",
            "get-task-allow": getTaskAllow,
        ]
        if !appGroups.isEmpty {
            entitlements["com.apple.security.application-groups"] = appGroups
        }
        if healthKit {
            entitlements["com.apple.developer.healthkit"] = true
        }
        var plist: [String: Any] = [
            "Name": "Tagwerk Test",
            "TeamName": "Max Mustermann",
            "TeamIdentifier": ["ABCDE12345"],
            "CreationDate": created,
            "ExpirationDate": expires,
            "Entitlements": entitlements,
        ]
        if allDevices {
            plist["ProvisionsAllDevices"] = true
        } else {
            plist["ProvisionedDevices"] = ["00008120-000000000000001E"]
        }
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return Data([0x30, 0x82, 0x1F, 0x00, 0x06, 0x09]) + xml + Data([0xA0, 0x82, 0x00, 0x31])
    }

    private let created = Date(timeIntervalSince1970: 1_760_000_000)

    @Test func parsesFreeAppleIDProfile() throws {
        let data = try makeProfileData(created: created, expires: created.addingTimeInterval(7 * 86_400))
        let profile = try ProvisioningProfile.parse(data)

        #expect(profile.name == "Tagwerk Test")
        #expect(profile.teamIdentifiers == ["ABCDE12345"])
        #expect(profile.getTaskAllow)
        #expect(profile.appGroups == ["group.de.tagwerk.app.ABCDE12345"])
        #expect(profile.hasHealthKit)
        #expect(profile.provisionedDeviceCount == 1)
        #expect(profile.kind == .freeAppleID)
        #expect(profile.expirationDate == created.addingTimeInterval(7 * 86_400))
    }

    @Test func detectsPaidDevelopmentProfile() throws {
        let data = try makeProfileData(created: created, expires: created.addingTimeInterval(365 * 86_400))
        #expect(try ProvisioningProfile.parse(data).kind == .development)
    }

    @Test func detectsAdHocAndEnterprise() throws {
        let adHoc = try makeProfileData(created: created, expires: created.addingTimeInterval(365 * 86_400), getTaskAllow: false)
        #expect(try ProvisioningProfile.parse(adHoc).kind == .adHoc)

        let enterprise = try makeProfileData(created: created, expires: created.addingTimeInterval(365 * 86_400), getTaskAllow: false, allDevices: true)
        #expect(try ProvisioningProfile.parse(enterprise).kind == .enterprise)
    }

    @Test func missingEntitlementsAreReported() throws {
        let data = try makeProfileData(
            created: created, expires: created.addingTimeInterval(7 * 86_400),
            appGroups: [], healthKit: false
        )
        let profile = try ProvisioningProfile.parse(data)
        #expect(!profile.hasHealthKit)
        #expect(!profile.hasAppGroups)
    }

    @Test func garbageThrows() {
        #expect(throws: ProvisioningProfileError.plistNotFound) {
            try ProvisioningProfile.parse(Data("kein profil".utf8))
        }
        #expect(throws: ProvisioningProfileError.invalidPlist) {
            try ProvisioningProfile.parse(Data("<?xml kaputt </plist>".utf8))
        }
    }

    @Test func signingStatusLevelsAndTexts() {
        let expires = created.addingTimeInterval(7 * 86_400)
        let status = SigningStatus(kind: .freeAppleID, expirationDate: expires)

        #expect(status.level(now: created) == .ok)
        #expect(status.remainingText(now: created) == "noch 7 Tage")

        let thirtyHoursLeft = expires.addingTimeInterval(-30 * 3_600)
        #expect(status.level(now: thirtyHoursLeft) == .expiresSoon)
        #expect(status.remainingText(now: thirtyHoursLeft) == "noch 1 Tag")

        let fiveHoursLeft = expires.addingTimeInterval(-5 * 3_600)
        #expect(status.remainingText(now: fiveHoursLeft) == "noch 5 Std.")

        let tenMinutesLeft = expires.addingTimeInterval(-600)
        #expect(status.remainingText(now: tenMinutesLeft) == "unter 1 Std.")

        let afterExpiry = expires.addingTimeInterval(60)
        #expect(status.level(now: afterExpiry) == .expired)
        #expect(status.remainingText(now: afterExpiry) == "abgelaufen")
    }

    @Test func signingStatusWithoutProfile() {
        let status = SigningStatus(profile: nil)
        #expect(status.kind == .none)
        #expect(status.level(now: created) == .unknown)
        #expect(status.remainingText(now: created) == "kein Ablaufdatum")
    }
}

@Suite("App-Group-Auflösung")
struct AppGroupResolverTests {
    @Test func usesDefaultWithoutSideloading() {
        #expect(AppGroupResolver.resolve(infoDictionary: [:]) == TagwerkIDs.appGroup)
        #expect(AppGroupResolver.resolve(infoDictionary: nil) == TagwerkIDs.appGroup)
        #expect(!AppGroupResolver.isSideloaded(infoDictionary: [:]))
    }

    @Test func prefersRenamedGroupFromSideStore() {
        let info: [String: Any] = [
            "ALTAppGroups": ["group.other.thing", "group.de.tagwerk.app.ABCDE12345"],
        ]
        #expect(AppGroupResolver.resolve(infoDictionary: info) == "group.de.tagwerk.app.ABCDE12345")
        #expect(AppGroupResolver.isSideloaded(infoDictionary: info))
    }

    @Test func fallsBackToFirstSideloadedGroup() {
        let info: [String: Any] = ["ALTAppGroups": ["group.renamed.XYZ"]]
        #expect(AppGroupResolver.resolve(infoDictionary: info) == "group.renamed.XYZ")
    }

    /// iloader schreibt kein `ALTAppGroups`, die umbenannte ID steht nur im Profil
    /// (so auf dem iPhone im ersten Systemcheck gesehen).
    @Test func usesRenamedGroupFromProfile() {
        let resolved = AppGroupResolver.resolve(
            infoDictionary: [:],
            profileAppGroups: ["group.de.tagwerk.app.L6STM8N2CH"]
        )
        #expect(resolved == "group.de.tagwerk.app.L6STM8N2CH")
    }

    @Test func infoPlistWinsOverProfileAndWildcardsAreIgnored() {
        let info: [String: Any] = ["ALTAppGroups": ["group.de.tagwerk.app.FROMINFO"]]
        #expect(
            AppGroupResolver.resolve(infoDictionary: info, profileAppGroups: ["group.de.tagwerk.app.FROMPROFILE"])
                == "group.de.tagwerk.app.FROMINFO"
        )
        #expect(AppGroupResolver.resolve(infoDictionary: nil, profileAppGroups: ["group.*"]) == TagwerkIDs.appGroup)
    }

    @Test func paidProfileKeepsFixedGroup() {
        #expect(AppGroupResolver.resolve(infoDictionary: nil, profileAppGroups: [TagwerkIDs.appGroup]) == TagwerkIDs.appGroup)
    }

    @Test func doesNotMatchSimilarPrefix() {
        let info: [String: Any] = ["ALTAppGroups": ["group.de.tagwerk.application", "group.de.tagwerk.app"]]
        #expect(AppGroupResolver.resolve(infoDictionary: info) == "group.de.tagwerk.app")
    }
}
