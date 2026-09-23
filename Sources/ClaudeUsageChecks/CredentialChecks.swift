import Foundation
import ClaudeUsageCore

/// Source de jeton qui compte ses lectures, pour vérifier la mise en mémoire.
private final class CountingSource: CredentialProviding, @unchecked Sendable {
    private(set) var reads = 0

    func accessToken() throws -> String {
        reads += 1
        return "jeton-\(reads)"
    }
}

/// Vérifications de la lecture du jeton stocké par Claude Code.
///
/// Le trousseau lui-même n'est pas sollicité : il ouvrirait une boîte de
/// dialogue système. Seul le décodage du secret est vérifié.
func runCredentialChecks(_ runner: inout CheckRunner) {

    runner.check("le jeton est extrait du JSON du trousseau") { a in
        let payload = #"{"claudeAiOauth": {"accessToken": "abc123", "refreshToken": "xyz"}}"#
            .data(using: .utf8)!
        a.expectEqual(try CredentialPayloadDecoder.accessToken(from: payload), "abc123")
    }

    runner.check("un JSON sans jeton est refusé") { a in
        let payload = #"{"claudeAiOauth": {"refreshToken": "xyz"}}"#.data(using: .utf8)!
        a.expectThrows(UsageError.credentialsNotFound) {
            _ = try CredentialPayloadDecoder.accessToken(from: payload)
        }
    }

    runner.check("un jeton vide est refusé") { a in
        let payload = #"{"claudeAiOauth": {"accessToken": ""}}"#.data(using: .utf8)!
        a.expectThrows(UsageError.credentialsNotFound) {
            _ = try CredentialPayloadDecoder.accessToken(from: payload)
        }
    }

    runner.check("un contenu illisible est refusé") { a in
        let payload = "pas du json".data(using: .utf8)!
        a.expectThrows(UsageError.credentialsNotFound) {
            _ = try CredentialPayloadDecoder.accessToken(from: payload)
        }
    }

    runner.check("le jeton gardé en mémoire n'est lu qu'une fois") { a in
        let source = CountingSource()
        let store = CachedCredentialStore(source: source)
        a.expectEqual(try store.accessToken(), "jeton-1")
        a.expectEqual(try store.accessToken(), "jeton-1")
        a.expectEqual(source.reads, 1)
    }

    runner.check("après invalidation, le jeton est relu") { a in
        let source = CountingSource()
        let store = CachedCredentialStore(source: source)
        _ = try store.accessToken()
        store.invalidate()
        a.expectEqual(try store.accessToken(), "jeton-2")
    }
}
