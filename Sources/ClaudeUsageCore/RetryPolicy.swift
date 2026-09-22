import Foundation

/// Décide combien de temps attendre après un refus pour trop de requêtes.
///
/// Sans indication du serveur, l'attente double à chaque refus consécutif :
/// une minute, deux, quatre… jusqu'à une demi-heure au plus.
public struct RetryPolicy: Sendable {

    /// Attente minimale, et point de départ du doublement.
    public static let minimumDelay: TimeInterval = 60
    /// Attente maximale, quel que soit le nombre de refus.
    public static let maximumDelay: TimeInterval = 1800

    private var consecutiveRefusals = 0

    public init() {}

    /// Enregistre un refus et renvoie l'attente à observer avant le prochain essai.
    public mutating func delayAfterRateLimit(retryAfter: TimeInterval?) -> TimeInterval {
        let doubled = Self.minimumDelay * pow(2, Double(consecutiveRefusals))
        consecutiveRefusals += 1
        let automatic = min(doubled, Self.maximumDelay)
        guard let retryAfter else { return automatic }
        return min(max(retryAfter, Self.minimumDelay), Self.maximumDelay)
    }

    /// Oublie les refus passés, après une récupération réussie.
    public mutating func reset() {
        consecutiveRefusals = 0
    }
}
