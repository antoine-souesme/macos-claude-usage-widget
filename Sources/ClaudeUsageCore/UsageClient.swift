import Foundation

/// Récupère l'utilisation courante du plan.
public protocol UsageFetching: Sendable {
    /// Interroge la source de données et renvoie un instantané.
    func fetch() async throws -> UsageSnapshot
}

/// Exécute une requête HTTP. Extrait en protocole pour rester vérifiable sans réseau.
public protocol HTTPTransporting: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Transport réel, adossé à `URLSession`.
public struct URLSessionTransport: HTTPTransporting {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.malformedResponse
        }
        return (data, http)
    }
}

/// Interroge l'API d'utilisation d'Anthropic avec le jeton de la session Claude Code.
public struct APIUsageClient: UsageFetching {

    /// Adresse du point d'accès renvoyant l'utilisation du plan.
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let credentials: CredentialProviding
    private let transport: HTTPTransporting

    public init(credentials: CredentialProviding, transport: HTTPTransporting) {
        self.credentials = credentials
        self.transport = transport
    }

    public func fetch() async throws -> UsageSnapshot {
        let token = try credentials.accessToken()

        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as UsageError {
            throw error
        } catch {
            throw UsageError.network(error.localizedDescription)
        }

        switch response.statusCode {
        case 200...299:
            return try UsageResponseDecoder.decode(data)
        case 401, 403:
            // Le jeton a sans doute été renouvelé par Claude Code : il sera relu au prochain essai.
            credentials.invalidate()
            throw UsageError.sessionExpired
        case 429:
            throw UsageError.rateLimited(retryAfter: Self.retryDelay(from: response))
        default:
            throw UsageError.network("code \(response.statusCode)")
        }
    }

    /// Lit l'en-tête `Retry-After` quand il contient un nombre de secondes.
    /// Toute autre forme est ignorée : le ralentissement automatique prendra le relais.
    private static func retryDelay(from response: HTTPURLResponse) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)),
              seconds > 0
        else { return nil }
        return seconds
    }
}
