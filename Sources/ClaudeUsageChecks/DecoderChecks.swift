import Foundation
import ClaudeUsageCore

/// Réponse réduite mais fidèle à la forme réelle de l'API.
let validPayload = """
{
  "five_hour": {"utilization": 10.0, "resets_at": "2026-09-22T11:30:00.407049+00:00", "limit_dollars": null},
  "seven_day": {"utilization": 2.5, "resets_at": "2026-09-28T20:00:00.407077+00:00", "limit_dollars": null},
  "seven_day_opus": null,
  "extra_usage": {"is_enabled": false}
}
""".data(using: .utf8)!

/// Vérifications du décodage de la réponse de l'API.
func runDecoderChecks(_ runner: inout CheckRunner) {

    runner.check("une réponse valide donne les deux pourcentages") { a in
        let snapshot = try UsageResponseDecoder.decode(validPayload)
        a.expectEqual(snapshot.fiveHour.utilization, 10.0, "limite 5 h")
        a.expectEqual(snapshot.sevenDay.utilization, 2.5, "limite hebdomadaire")
    }

    runner.check("les dates de remise à zéro sont décodées") { a in
        let snapshot = try UsageResponseDecoder.decode(validPayload)
        let expected = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026, month: 9, day: 22, hour: 11, minute: 30
        ).date!
        guard let actual = a.require(snapshot.fiveHour.resetsAt, "date de remise à zéro") else { return }
        a.expect(abs(actual.timeIntervalSince(expected)) < 1, "date éloignée de l'attendu : \(actual)")
    }

    runner.check("une date absente devient nil sans échouer") { a in
        let payload = """
        {"five_hour": {"utilization": 0.0, "resets_at": null},
         "seven_day": {"utilization": 0.0, "resets_at": null}}
        """.data(using: .utf8)!
        let snapshot = try UsageResponseDecoder.decode(payload)
        a.expect(snapshot.fiveHour.resetsAt == nil, "5 h devrait être nil")
        a.expect(snapshot.sevenDay.resetsAt == nil, "hebdomadaire devrait être nil")
    }

    runner.check("un JSON sans les champs attendus est refusé") { a in
        let payload = #"{"seven_day": {"utilization": 2.0}}"#.data(using: .utf8)!
        a.expectThrows(UsageError.malformedResponse) { _ = try UsageResponseDecoder.decode(payload) }
    }

    runner.check("un contenu illisible est refusé") { a in
        let payload = "pas du json".data(using: .utf8)!
        a.expectThrows(UsageError.malformedResponse) { _ = try UsageResponseDecoder.decode(payload) }
    }
}
