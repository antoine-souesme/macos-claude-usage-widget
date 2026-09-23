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
    /// Renvoie `nil` en dessous du seuil d'alerte : sans couleur imposée, macOS
    /// grise lui-même le texte quand la barre de menus n'est pas celle de l'écran actif.
    public static func statusColor(for snapshot: UsageSnapshot) -> NSColor? {
        let highest = max(snapshot.fiveHour.utilization, snapshot.sevenDay.utilization)
        if highest >= criticalThreshold { return .systemRed }
        if highest >= warningThreshold { return .systemOrange }
        return nil
    }

    /// Phrase indiquant la date et l'heure locales de remise à zéro, ou rien si elles sont inconnues.
    ///
    /// Le jour est remplacé par « today » quand la remise à zéro a lieu aujourd'hui.
    /// `now` et `calendar` sont paramétrables pour rendre la fonction vérifiable.
    public static func resetText(
        for date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        guard let date else { return nil }
        let time = formatter("HH:mm", calendar: calendar).string(from: date)
        if calendar.isDate(date, inSameDayAs: now) {
            return "Resets today at \(time)"
        }
        let day = formatter("dd/MM/yyyy", calendar: calendar).string(from: date)
        return "Resets \(day) at \(time)"
    }

    /// Formateur à motif fixe, indépendant des réglages régionaux de l'utilisateur.
    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }

    /// Message affiché dans le menu lorsqu'une récupération a échoué.
    ///
    /// `retryIn` indique l'attente restante avant le prochain essai, en secondes,
    /// quand un ralentissement est en cours.
    public static func message(for error: UsageError, retryIn: TimeInterval? = nil) -> String {
        switch error {
        case .credentialsNotFound:
            return "Session not found. Launch Claude Code and try again."
        case .sessionExpired:
            return "Session expired. Relaunch Claude Code to sign in again."
        case .rateLimited:
            guard let retryIn, retryIn > 0 else {
                return "Too many requests. Retrying shortly."
            }
            let minutes = max(1, Int((retryIn / 60).rounded()))
            return "Too many requests. Retrying in \(minutes) min."
        case .network(let detail):
            return "Unable to connect (\(detail))."
        case .malformedResponse:
            return "Unexpected server response."
        }
    }
}
