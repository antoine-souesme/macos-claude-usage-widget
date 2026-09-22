import Foundation

/// Transforme la réponse JSON de l'API d'utilisation en `UsageSnapshot`.
///
/// La réponse réelle contient de nombreux champs facultatifs ; seuls
/// `five_hour` et `seven_day` sont lus, tout le reste est ignoré.
public enum UsageResponseDecoder {

    /// Forme d'une limite telle que l'API la renvoie.
    private struct RawLimit: Decodable {
        let utilization: Double
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    /// Enveloppe ne retenant que les deux limites qui nous intéressent.
    private struct RawResponse: Decodable {
        let fiveHour: RawLimit
        let sevenDay: RawLimit

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    /// Décode les données brutes de l'API.
    /// - Throws: `UsageError.malformedResponse` si la forme attendue est absente.
    public static func decode(_ data: Data) throws -> UsageSnapshot {
        guard let raw = try? JSONDecoder().decode(RawResponse.self, from: data) else {
            throw UsageError.malformedResponse
        }
        return UsageSnapshot(
            fiveHour: UsageLimit(
                utilization: raw.fiveHour.utilization,
                resetsAt: parseDate(raw.fiveHour.resetsAt)
            ),
            sevenDay: UsageLimit(
                utilization: raw.sevenDay.utilization,
                resetsAt: parseDate(raw.sevenDay.resetsAt)
            )
        )
    }

    /// Convertit une date ISO 8601 facultative, en tolérant l'absence de fraction de seconde.
    /// Les formateurs sont créés à chaque appel plutôt que partagés : ils ne sont
    /// pas sûrs entre fils d'exécution, et une seule date est décodée par minute.
    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
