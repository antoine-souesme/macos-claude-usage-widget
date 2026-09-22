import Foundation

/// Une limite d'utilisation : son pourcentage courant et l'instant de sa remise à zéro.
public struct UsageLimit: Equatable, Sendable {
    /// Pourcentage consommé, de 0 à 100.
    public let utilization: Double
    /// Instant de remise à zéro, absent si l'API ne le fournit pas.
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

/// Photographie de l'utilisation du plan à un instant donné.
public struct UsageSnapshot: Equatable, Sendable {
    /// Limite glissante sur cinq heures.
    public let fiveHour: UsageLimit
    /// Limite glissante sur sept jours.
    public let sevenDay: UsageLimit

    public init(fiveHour: UsageLimit, sevenDay: UsageLimit) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

/// Les échecs possibles lors de la récupération de l'utilisation.
public enum UsageError: Error, Equatable, Sendable {
    /// Aucun élément de trousseau n'a été trouvé pour Claude Code.
    case credentialsNotFound
    /// Le jeton existe mais l'API le refuse : la session doit être renouvelée.
    case sessionExpired
    /// La requête réseau a échoué ; le texte décrit la cause.
    case network(String)
    /// La réponse de l'API n'a pas la forme attendue.
    case malformedResponse
}
