//
//  TripCanonicalWireTests.swift
//  LicensePlateAppTests
//
//  Step 12.5 — Round-trip and JSON golden fixtures for trip canonical DTOs.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct TripCanonicalWireTests {

    @Test
    func session_roundTrip_preservesFields() {
        let p0 = Date(timeIntervalSince1970: 1_700_000_000)
        let session = TripSession(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            name: "Road Trip",
            status: .active,
            createdAt: p0,
            createdBy: "owner-uid",
            startedAt: p0.addingTimeInterval(60),
            endedAt: nil,
            endedBy: nil,
            participants: [
                TripParticipant(userId: "owner-uid", role: .owner, joinedAt: p0),
                TripParticipant(userId: "member-uid", role: .member, joinedAt: p0.addingTimeInterval(120)),
            ],
            riskFlags: nil
        )
        let wire = TripCanonicalMapper.wireSession(from: session)
        let decoded = TripCanonicalMapper.domainSession(from: wire)
        #expect(decoded.id == session.id)
        #expect(decoded.name == session.name)
        #expect(decoded.status == session.status)
        #expect(decoded.createdBy == session.createdBy)
        #expect(decoded.participants.count == 2)
        #expect(decoded.participants[0].userId == "owner-uid")
        #expect(decoded.participants[0].role == .owner)
    }

    @Test
    func session_jsonRoundTrip() throws {
        let json = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "name": "Test",
          "status": "created",
          "createdAt": 1700000000,
          "createdBy": "u1",
          "startedAt": null,
          "endedAt": null,
          "endedBy": null,
          "participants": [
            { "userId": "u1", "role": "owner", "joinedAt": 1700000000, "leftAt": null, "teamId": null }
          ]
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(TripSessionWireDTO.self, from: json)
        let domain = TripCanonicalMapper.domainSession(from: dto)
        #expect(domain.name == "Test")
        #expect(domain.participants.first?.role == .owner)
        let reencoded = try JSONEncoder().encode(dto)
        let dto2 = try JSONDecoder().decode(TripSessionWireDTO.self, from: reencoded)
        #expect(dto2 == dto)
    }

    @Test
    func session_encodeDecoded_matchesGolden() throws {
        let dto = TripSessionWireDTO(
            id: "11111111-2222-3333-4444-555555555555",
            name: "Test",
            status: "created",
            createdAt: 1_700_000_000,
            createdBy: "u1",
            startedAt: nil,
            endedAt: nil,
            endedBy: nil,
            participants: [
                TripParticipantWireItem(userId: "u1", role: "owner", joinedAt: 1_700_000_000, leftAt: nil, teamId: nil),
            ]
        )
        let data = try JSONEncoder().encode(dto)
        let back = try JSONDecoder().decode(TripSessionWireDTO.self, from: data)
        #expect(back == dto)
    }

    @Test
    func game_roundTrip_withBinaryPayloads() throws {
        let ruleSet = GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue)
        let config = CommonGameConfig()
        let ruleData = try JSONEncoder().encode(ruleSet)
        let commonData = try JSONEncoder().encode(config)
        let instance = GameInstance(
            id: UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            endedAt: nil,
            ruleSet: ruleSet,
            commonConfig: config,
            gameSpecificPayloadType: "license_plate",
            gameSpecificPayloadVersion: "1",
            gameSpecificPayloadData: Data([0x01, 0x02]),
            teams: []
        )
        let wire = TripCanonicalMapper.wireGame(from: instance)
        let back = try TripCanonicalMapper.domainGame(from: wire)
        #expect(back.id == instance.id)
        #expect(back.definitionId == instance.definitionId)
        #expect(back.sessionId == instance.sessionId)
        #expect(back.gameSpecificPayloadData == instance.gameSpecificPayloadData)
    }

    @Test
    func event_roundTrip() {
        let sid = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let ev = TripActivityEvent(
            id: "evt-1",
            sessionId: sid,
            kind: .regionFound,
            timestamp: Date(timeIntervalSince1970: 1_900_000_000),
            actorId: "u1",
            payload: ["regionId": "CA", "gameInstanceId": UUID().uuidString]
        )
        let wire = TripCanonicalMapper.wireEvent(from: ev)
        let back = TripCanonicalMapper.domainEvent(from: wire)
        #expect(back?.id == ev.id)
        #expect(back?.kind == ev.kind)
        #expect(back?.payload?["regionId"] == "CA")
    }

    @Test
    func bootstrap_bundle_decodes() throws {
        let json = """
        {
          "session": {
            "id": "11111111-2222-3333-4444-555555555555",
            "name": "T",
            "status": "active",
            "createdAt": 1700000000,
            "createdBy": "u1",
            "startedAt": 1700000060,
            "endedAt": null,
            "endedBy": null,
            "participants": []
          },
          "games": [],
          "events": [],
          "syncVersion": 3,
          "nextEventCursor": null
        }
        """.data(using: .utf8)!
        let bundle = try JSONDecoder().decode(TripBootstrapWireDTO.self, from: json)
        #expect(bundle.syncVersion == 3)
        #expect(bundle.session.name == "T")
    }
}
