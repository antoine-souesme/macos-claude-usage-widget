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

    runner.check("en dessous de 70 % la couleur reste celle du système") { a in
        a.expectEqual(UsageFormatter.statusColor(for: makeSnapshot(fiveHour: 69, sevenDay: 0)), NSColor.labelColor)
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

    runner.check("une date de remise à zéro devient une phrase lisible") { a in
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        guard let text = a.require(UsageFormatter.resetText(for: date), "texte de remise à zéro") else { return }
        a.expect(text.hasPrefix("Réinitialisation à "), "préfixe inattendu : \(text)")
    }

    runner.check("une date absente ne produit aucun texte") { a in
        a.expect(UsageFormatter.resetText(for: nil) == nil, "devrait être nil")
    }

    runner.check("chaque erreur a son propre message en français") { a in
        a.expect(UsageFormatter.message(for: .credentialsNotFound).contains("Claude Code"), "session introuvable")
        a.expect(UsageFormatter.message(for: .sessionExpired).contains("Claude Code"), "session expirée")
        a.expect(!UsageFormatter.message(for: .network("timeout")).isEmpty, "réseau")
        a.expect(!UsageFormatter.message(for: .malformedResponse).isEmpty, "réponse illisible")
    }

    runner.check("le texte de repli est une ellipse") { a in
        a.expectEqual(UsageFormatter.placeholderText, "…")
    }
}
