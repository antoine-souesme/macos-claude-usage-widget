import Foundation
import ClaudeUsageCore

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
}
