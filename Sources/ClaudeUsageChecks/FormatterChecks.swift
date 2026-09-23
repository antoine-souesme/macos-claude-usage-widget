import Foundation
import AppKit
import ClaudeUsageCore

/// Construit un instantané sans date, pour alléger les cas de vérification.
private func makeSnapshot(fiveHour: Double, sevenDay: Double) -> UsageSnapshot {
    UsageSnapshot(
        fiveHour: UsageLimit(utilization: fiveHour, resetsAt: nil),
        sevenDay: UsageLimit(utilization: sevenDay, resetsAt: nil)
    )
}

/// Vérifications de la mise en forme de l'affichage.
func runFormatterChecks(_ runner: inout CheckRunner) {

    runner.check("le texte montre les deux pourcentages séparés par un point médian") { a in
        a.expectEqual(UsageFormatter.statusText(for: makeSnapshot(fiveHour: 10, sevenDay: 2)), "10% · 2%")
    }

    runner.check("les pourcentages sont arrondis à l'entier le plus proche") { a in
        a.expectEqual(UsageFormatter.statusText(for: makeSnapshot(fiveHour: 10.4, sevenDay: 2.5)), "10% · 3%")
        a.expectEqual(UsageFormatter.percentText(0), "0%")
        a.expectEqual(UsageFormatter.percentText(99.9), "100%")
    }

    runner.check("en dessous de 70 % aucune couleur n'est imposée") { a in
        a.expectEqual(UsageFormatter.statusColor(for: makeSnapshot(fiveHour: 69, sevenDay: 0)), nil)
    }

    runner.check("à partir de 70 % la couleur passe à l'orange") { a in
        a.expectEqual(UsageFormatter.statusColor(for: makeSnapshot(fiveHour: 70, sevenDay: 0)), NSColor.systemOrange)
        a.expectEqual(UsageFormatter.statusColor(for: makeSnapshot(fiveHour: 0, sevenDay: 89)), NSColor.systemOrange)
    }

    runner.check("à partir de 90 % la couleur passe au rouge") { a in
        a.expectEqual(UsageFormatter.statusColor(for: makeSnapshot(fiveHour: 0, sevenDay: 90)), NSColor.systemRed)
    }

    runner.check("la couleur suit la plus élevée des deux limites") { a in
        a.expectEqual(UsageFormatter.statusColor(for: makeSnapshot(fiveHour: 95, sevenDay: 3)), NSColor.systemRed)
    }

    runner.check("une remise à zéro un autre jour affiche la date et l'heure") { a in
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 10))!
        let reset = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 7, minute: 5))!
        a.expectEqual(
            UsageFormatter.resetText(for: reset, now: now, calendar: calendar),
            "Resets 28/09/2026 at 07:05"
        )
    }

    runner.check("une remise à zéro dans la journée affiche « today »") { a in
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 10))!
        let reset = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 14, minute: 30))!
        a.expectEqual(
            UsageFormatter.resetText(for: reset, now: now, calendar: calendar),
            "Resets today at 14:30"
        )
    }

    runner.check("une date absente ne produit aucun texte") { a in
        a.expect(UsageFormatter.resetText(for: nil) == nil, "devrait être nil")
    }

    runner.check("chaque erreur a son propre message en anglais") { a in
        a.expect(UsageFormatter.message(for: .credentialsNotFound).contains("Claude Code"), "session introuvable")
        a.expect(UsageFormatter.message(for: .sessionExpired).contains("Claude Code"), "session expirée")
        a.expect(!UsageFormatter.message(for: .network("timeout")).isEmpty, "réseau")
        a.expect(!UsageFormatter.message(for: .malformedResponse).isEmpty, "réponse illisible")
        a.expect(UsageFormatter.message(for: .rateLimited(retryAfter: nil)).contains("Too many requests"), "limite de requêtes")
    }

    runner.check("le message de limite annonce le délai avant le prochain essai") { a in
        a.expectEqual(
            UsageFormatter.message(for: .rateLimited(retryAfter: 120), retryIn: 120),
            "Too many requests. Retrying in 2 min."
        )
        a.expectEqual(
            UsageFormatter.message(for: .rateLimited(retryAfter: 45), retryIn: 45),
            "Too many requests. Retrying in 1 min."
        )
    }

    runner.check("sans délai connu le message reste vague") { a in
        a.expectEqual(
            UsageFormatter.message(for: .rateLimited(retryAfter: nil)),
            "Too many requests. Retrying shortly."
        )
    }

    runner.check("le texte de repli est une ellipse") { a in
        a.expectEqual(UsageFormatter.placeholderText, "…")
    }
}
