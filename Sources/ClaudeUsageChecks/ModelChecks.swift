import Foundation
import ClaudeUsageCore

/// Vérifications des types de base.
func runModelChecks(_ runner: inout CheckRunner) {

    runner.check("deux instantanés identiques sont égaux") { a in
        let date = Date(timeIntervalSince1970: 1_000)
        let first = UsageSnapshot(
            fiveHour: UsageLimit(utilization: 10, resetsAt: date),
            sevenDay: UsageLimit(utilization: 2, resetsAt: nil)
        )
        let second = UsageSnapshot(
            fiveHour: UsageLimit(utilization: 10, resetsAt: date),
            sevenDay: UsageLimit(utilization: 2, resetsAt: nil)
        )
        a.expectEqual(first, second)
    }

    runner.check("les cas d'erreur se comparent par valeur") { a in
        a.expectEqual(UsageError.credentialsNotFound, UsageError.credentialsNotFound)
        a.expect(UsageError.network("timeout") != UsageError.network("offline"), "réseau distinct")
    }
}
