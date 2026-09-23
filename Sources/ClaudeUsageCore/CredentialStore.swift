import Foundation
import Security

/// Fournit le jeton d'accès nécessaire à l'appel de l'API.
public protocol CredentialProviding: Sendable {
    /// Renvoie le jeton d'accès courant.
    /// - Throws: `UsageError.credentialsNotFound` s'il est absent ou illisible.
    func accessToken() throws -> String

    /// Oublie le jeton éventuellement gardé en mémoire, pour forcer une relecture.
    func invalidate()
}

extension CredentialProviding {
    public func invalidate() {}
}

/// Décode le contenu JSON enregistré par Claude Code dans le trousseau.
public enum CredentialPayloadDecoder {

    /// Forme du secret stocké par Claude Code.
    private struct Payload: Decodable {
        struct OAuth: Decodable {
            let accessToken: String?
        }
        let claudeAiOauth: OAuth
    }

    /// Extrait le jeton d'accès du secret brut.
    /// - Throws: `UsageError.credentialsNotFound` si le jeton est absent ou vide.
    public static func accessToken(from data: Data) throws -> String {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let token = payload.claudeAiOauth.accessToken,
              !token.isEmpty
        else {
            throw UsageError.credentialsNotFound
        }
        return token
    }
}

/// Lit le jeton dans le trousseau macOS, à l'endroit où Claude Code l'enregistre.
public struct KeychainCredentialStore: CredentialProviding {

    /// Nom du service sous lequel Claude Code range ses identifiants.
    private let service = "Claude Code-credentials"

    public init() {}

    public func accessToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw UsageError.credentialsNotFound
        }
        return try CredentialPayloadDecoder.accessToken(from: data)
    }
}

/// Garde en mémoire le jeton lu par une autre source, pour ne pas la solliciter à chaque requête.
///
/// Chaque lecture du trousseau peut ouvrir une demande de mot de passe : le
/// jeton n'est donc relu qu'au premier appel, puis après un `invalidate()`.
public final class CachedCredentialStore: CredentialProviding, @unchecked Sendable {

    private let source: CredentialProviding
    private let lock = NSLock()
    private var cachedToken: String?

    public init(source: CredentialProviding) {
        self.source = source
    }

    public func accessToken() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cachedToken { return cachedToken }
        let token = try source.accessToken()
        cachedToken = token
        return token
    }

    public func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cachedToken = nil
    }
}
