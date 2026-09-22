import Foundation
import ClaudeUsageCore

/// Vérifications du ralentissement appliqué après un refus pour trop de requêtes.
func runBackoffChecks(_ runner: inout CheckRunner) {

    runner.check("le délai indiqué par le serveur est respecté") { a in
        var policy = RetryPolicy()
        a.expectEqual(policy.delayAfterRateLimit(retryAfter: 300), 300)
    }

    runner.check("sans indication du serveur le délai double à chaque refus") { a in
        var policy = RetryPolicy()
        a.expectEqual(policy.delayAfterRateLimit(retryAfter: nil), 60)
        a.expectEqual(policy.delayAfterRateLimit(retryAfter: nil), 120)
        a.expectEqual(policy.delayAfterRateLimit(retryAfter: nil), 240)
    }

    runner.check("le délai ne dépasse jamais une demi-heure") { a in
        var policy = RetryPolicy()
        for _ in 0..<20 { _ = policy.delayAfterRateLimit(retryAfter: nil) }
        a.expectEqual(policy.delayAfterRateLimit(retryAfter: nil), 1800)
    }

    runner.check("une réussite remet le compteur à zéro") { a in
        var policy = RetryPolicy()
        _ = policy.delayAfterRateLimit(retryAfter: nil)
        _ = policy.delayAfterRateLimit(retryAfter: nil)
        policy.reset()
        a.expectEqual(policy.delayAfterRateLimit(retryAfter: nil), 60)
    }

    runner.check("un délai trop court venant du serveur est relevé au minimum") { a in
        var policy = RetryPolicy()
        a.expectEqual(policy.delayAfterRateLimit(retryAfter: 5), 60)
    }
}
