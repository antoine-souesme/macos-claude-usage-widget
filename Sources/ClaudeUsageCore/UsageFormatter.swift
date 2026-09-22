import Foundation
import AppKit

/// Met en forme un instantané d'utilisation pour l'affichage.
///
/// Fonctions pures : aucun accès au réseau ni au disque, ce qui les rend
/// directement vérifiables.
public enum UsageFormatter {

    /// Seuil à partir duquel l'affichage passe en orange.
    private static let warningThreshold: Double = 70
    /// Seuil à partir duquel l'affichage passe en rouge.
    private static let criticalThreshold: Double = 90

    /// Texte affiché tant qu'aucune donnée n'a pu être récupérée.
    public static let placeholderText = "…"

    /// Texte de la barre de menus : limite 5 h puis limite hebdomadaire.
    public static func statusText(for snapshot: UsageSnapshot) -> String {
        "\(percentText(snapshot.fiveHour.utilization)) · \(percentText(snapshot.sevenDay.utilization))"
    }

    /// Un pourcentage arrondi à l'entier, suivi du signe pour cent.
    public static func percentText(_ utilization: Double) -> String {
        "\(Int(utilization.rounded()))%"
    }

    /// Couleur du texte, déterminée par la plus chargée des deux limites.
    public static func statusColor(for snapshot: UsageSnapshot) -> NSColor {
        let highest = max(snapshot.fiveHour.utilization, snapshot.sevenDay.utilization)
        if highest >= criticalThreshold { return .systemRed }
        if highest >= warningThreshold { return .systemOrange }
        return .labelColor
    }

    /// Phrase indiquant l'heure locale de remise à zéro, ou rien si elle est inconnue.
    public static func resetText(for date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Réinitialisation à \(formatter.string(from: date))"
    }

    /// Message affiché dans le menu lorsqu'une récupération a échoué.
    public static func message(for error: UsageError) -> String {
        switch error {
        case .credentialsNotFound:
            return "Session introuvable. Lance Claude Code puis réessaie."
        case .sessionExpired:
            return "Session expirée. Relance Claude Code pour te reconnecter."
        case .network(let detail):
            return "Connexion impossible (\(detail))."
        case .malformedResponse:
            return "Réponse inattendue du serveur."
        }
    }
}
