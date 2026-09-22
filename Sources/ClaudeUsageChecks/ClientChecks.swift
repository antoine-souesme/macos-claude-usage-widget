import Foundation
import ClaudeUsageCore

/// Doublure renvoyant un jeton fixe, ou une erreur si on ne lui en donne pas.
private struct StubCredentials: CredentialProviding {
    var token: String? = "test-token"

    func accessToken() throws -> String {
        guard let token else { throw UsageError.credentialsNotFound }
        return token
    }
}

/// Doublure de transport : retient la requête reçue et rejoue une réponse fixée.
private final class StubTransport: HTTPTransporting, @unchecked Sendable {
    var statusCode = 200
    var body = Data()
    var headers: [String: String] = [:]
    var thrownError: Error?
    private(set) var lastRequest: URLRequest?

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        if let thrownError { throw thrownError }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: headers
        )!
        return (body, response)
    }
}

private let samplePayload = """
{"five_hour": {"utilization": 42.0, "resets_at": null},
 "seven_day": {"utilization": 7.0, "resets_at": null}}
""".data(using: .utf8)!

/// Vérifications du client de l'API d'utilisation.
func runClientChecks(_ runner: inout CheckRunner) async {

    await runner.checkAsync("une réponse réussie donne l'instantané décodé") { a in
        let transport = StubTransport()
        transport.body = samplePayload
        let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
        let snapshot = try await client.fetch()
        a.expectEqual(snapshot.fiveHour.utilization, 42.0, "limite 5 h")
        a.expectEqual(snapshot.sevenDay.utilization, 7.0, "limite hebdomadaire")
    }

    await runner.checkAsync("la requête porte l'adresse et les en-têtes attendus") { a in
        let transport = StubTransport()
        transport.body = samplePayload
        let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
        _ = try await client.fetch()
        guard let request = a.require(transport.lastRequest, "requête envoyée") else { return }
        a.expectEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage", "adresse")
        a.expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token", "autorisation")
        a.expectEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20", "en-tête beta")
    }

    await runner.checkAsync("un jeton absent remonte sans appeler le réseau") { a in
        let transport = StubTransport()
        let client = APIUsageClient(credentials: StubCredentials(token: nil), transport: transport)
        await a.expectThrowsAsync(UsageError.credentialsNotFound) { _ = try await client.fetch() }
        a.expect(transport.lastRequest == nil, "le réseau n'aurait pas dû être sollicité")
    }

    await runner.checkAsync("un code 401 signale une session expirée") { a in
        let transport = StubTransport()
        transport.statusCode = 401
        let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
        await a.expectThrowsAsync(UsageError.sessionExpired) { _ = try await client.fetch() }
    }

    await runner.checkAsync("un code 500 devient une erreur réseau") { a in
        let transport = StubTransport()
        transport.statusCode = 500
        let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
        await a.expectThrowsAsync(UsageError.network("code 500")) { _ = try await client.fetch() }
    }

    await runner.checkAsync("un code 429 signale une limite de requêtes") { a in
        let transport = StubTransport()
        transport.statusCode = 429
        let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
        await a.expectThrowsAsync(UsageError.rateLimited(retryAfter: nil)) { _ = try await client.fetch() }
    }

    await runner.checkAsync("l'en-tête Retry-After en secondes est repris") { a in
        let transport = StubTransport()
        transport.statusCode = 429
        transport.headers = ["Retry-After": "120"]
        let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
        await a.expectThrowsAsync(UsageError.rateLimited(retryAfter: 120)) { _ = try await client.fetch() }
    }

    await runner.checkAsync("un Retry-After illisible est ignoré") { a in
        let transport = StubTransport()
        transport.statusCode = 429
        transport.headers = ["Retry-After": "bientôt"]
        let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
        await a.expectThrowsAsync(UsageError.rateLimited(retryAfter: nil)) { _ = try await client.fetch() }
    }

    await runner.checkAsync("une panne de transport devient une erreur réseau") { a in
        let transport = StubTransport()
        transport.thrownError = URLError(.notConnectedToInternet)
        let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
        do {
            _ = try await client.fetch()
            a.record("aucune erreur levée")
        } catch UsageError.network {
            return
        } catch {
            a.record("erreur inattendue : \(error)")
        }
    }

    await runner.checkAsync("un corps illisible est refusé") { a in
        let transport = StubTransport()
        transport.body = "pas du json".data(using: .utf8)!
        let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
        await a.expectThrowsAsync(UsageError.malformedResponse) { _ = try await client.fetch() }
    }
}
