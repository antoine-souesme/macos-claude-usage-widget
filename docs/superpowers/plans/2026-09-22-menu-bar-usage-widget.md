# Widget barre de menus « utilisation Claude » — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construire une application macOS sans fenêtre qui affiche en permanence, dans la barre de menus, le pourcentage d'utilisation de la limite 5 heures et celui de la limite hebdomadaire du plan Claude.

**Architecture:** Un paquet Swift Package Manager produisant un exécutable, empaqueté ensuite dans un bundle `.app` avec `LSUIElement`. Le jeton OAuth est lu dans le trousseau macOS, l'API d'utilisation d'Anthropic est interrogée toutes les 60 secondes, et le résultat est mis en forme par des fonctions pures avant d'alimenter un `NSStatusItem`. Le trousseau et le réseau sont derrière des protocoles pour rester testables.

**Tech Stack:** Swift 6.4, Swift Package Manager, Swift Testing (`import Testing`), AppKit, Security.framework, Foundation `URLSession`.

**Spec:** `docs/superpowers/specs/2026-09-22-menu-bar-usage-widget-design.md`

## Global Constraints

- Noms de types, de fonctions, de variables et de fichiers en anglais. Commentaires, documentation et `README.md` en français, accents compris.
- Plateforme minimale : `.macOS(.v14)`. Outil Swift : `// swift-tools-version: 6.0`.
- Aucune dépendance externe. Uniquement Foundation, AppKit, Security et Swift Testing.
- Nom du paquet et de l'exécutable : `ClaudeUsage`. Nom du bundle final : `ClaudeUsage.app`.
- Service du trousseau lu : `Claude Code-credentials`. Chemin du jeton dans le JSON : `claudeAiOauth.accessToken`.
- Point d'accès API : `https://api.anthropic.com/api/oauth/usage`, en-têtes `Authorization: Bearer <jeton>` et `anthropic-beta: oauth-2025-04-20`.
- Seuils de couleur : `< 70` défaut, `>= 70 et < 90` orange, `>= 90` rouge.
- Aucun jeton ne doit être écrit sur disque ni journalisé.
- Après chaque tâche, `swift build` et `swift test` doivent passer.

---

### Task 1: Squelette du paquet et modèle de données

**Files:**
- Create: `Package.swift`
- Create: `Sources/ClaudeUsage/UsageModels.swift`
- Create: `.gitignore`
- Test: `Tests/ClaudeUsageTests/UsageModelsTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces: `struct UsageLimit { let utilization: Double; let resetsAt: Date? }`, `struct UsageSnapshot { let fiveHour: UsageLimit; let sevenDay: UsageLimit }`, `enum UsageError: Error, Equatable { case credentialsNotFound, sessionExpired, network(String), malformedResponse }`. Les deux structures sont `Equatable` et `Sendable`.

- [ ] **Step 1: Créer `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

// Paquet exécutable : aucune dépendance externe, cible macOS 14 minimum.
let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClaudeUsage"),
        .testTarget(name: "ClaudeUsageTests", dependencies: ["ClaudeUsage"]),
    ]
)
```

- [ ] **Step 2: Créer `.gitignore`**

```
.build/
.swiftpm/
build/
*.app
.DS_Store
```

- [ ] **Step 3: Écrire le test qui échoue**

Créer `Tests/ClaudeUsageTests/UsageModelsTests.swift` :

```swift
import Testing
import Foundation
@testable import ClaudeUsage

@Test("Deux instantanés identiques sont égaux")
func snapshotEquality() {
    let date = Date(timeIntervalSince1970: 1_000)
    let first = UsageSnapshot(
        fiveHour: UsageLimit(utilization: 10, resetsAt: date),
        sevenDay: UsageLimit(utilization: 2, resetsAt: nil)
    )
    let second = UsageSnapshot(
        fiveHour: UsageLimit(utilization: 10, resetsAt: date),
        sevenDay: UsageLimit(utilization: 2, resetsAt: nil)
    )
    #expect(first == second)
}

@Test("Les cas d'erreur se comparent par valeur")
func errorEquality() {
    #expect(UsageError.credentialsNotFound == UsageError.credentialsNotFound)
    #expect(UsageError.network("timeout") != UsageError.network("offline"))
}
```

- [ ] **Step 4: Lancer les tests pour vérifier l'échec**

Run: `swift test`
Expected: échec de compilation, « cannot find 'UsageSnapshot' in scope ».

- [ ] **Step 5: Écrire le modèle minimal**

Créer `Sources/ClaudeUsage/UsageModels.swift` :

```swift
import Foundation

/// Une limite d'utilisation : son pourcentage courant et l'instant de sa remise à zéro.
struct UsageLimit: Equatable, Sendable {
    /// Pourcentage consommé, de 0 à 100.
    let utilization: Double
    /// Instant de remise à zéro, absent si l'API ne le fournit pas.
    let resetsAt: Date?
}

/// Photographie de l'utilisation du plan à un instant donné.
struct UsageSnapshot: Equatable, Sendable {
    /// Limite glissante sur cinq heures.
    let fiveHour: UsageLimit
    /// Limite glissante sur sept jours.
    let sevenDay: UsageLimit
}

/// Les échecs possibles lors de la récupération de l'utilisation.
enum UsageError: Error, Equatable, Sendable {
    /// Aucun élément de trousseau n'a été trouvé pour Claude Code.
    case credentialsNotFound
    /// Le jeton existe mais l'API le refuse : la session doit être renouvelée.
    case sessionExpired
    /// La requête réseau a échoué ; le texte décrit la cause.
    case network(String)
    /// La réponse de l'API n'a pas la forme attendue.
    case malformedResponse
}
```

- [ ] **Step 6: Lancer les tests pour vérifier le succès**

Run: `swift test`
Expected: les deux tests passent.

- [ ] **Step 7: Commit**

```bash
git add Package.swift .gitignore Sources/ClaudeUsage/UsageModels.swift Tests/ClaudeUsageTests/UsageModelsTests.swift
git commit -m "feat: squelette du paquet et modèle d'utilisation"
```

---

### Task 2: Décodage de la réponse de l'API

**Files:**
- Create: `Sources/ClaudeUsage/UsageResponseDecoder.swift`
- Test: `Tests/ClaudeUsageTests/UsageResponseDecoderTests.swift`

**Interfaces:**
- Consumes: `UsageSnapshot`, `UsageLimit`, `UsageError` (tâche 1).
- Produces: `enum UsageResponseDecoder { static func decode(_ data: Data) throws -> UsageSnapshot }`. Lance `UsageError.malformedResponse` si le JSON ne contient pas `five_hour.utilization` et `seven_day.utilization`.

Note pour l'implémenteur : la réponse réelle de l'API contient une trentaine de champs dont la plupart valent `null`. Le décodeur ne doit lire que `five_hour` et `seven_day` et ignorer tout le reste. `resets_at` est une date ISO 8601 avec fraction de seconde, par exemple `2026-09-22T11:30:00.407049+00:00`, et peut valoir `null`.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/ClaudeUsageTests/UsageResponseDecoderTests.swift` :

```swift
import Testing
import Foundation
@testable import ClaudeUsage

/// Réponse réduite mais fidèle à la forme réelle de l'API.
private let validPayload = """
{
  "five_hour": {"utilization": 10.0, "resets_at": "2026-09-22T11:30:00.407049+00:00", "limit_dollars": null},
  "seven_day": {"utilization": 2.5, "resets_at": "2026-09-28T20:00:00.407077+00:00", "limit_dollars": null},
  "seven_day_opus": null,
  "extra_usage": {"is_enabled": false}
}
""".data(using: .utf8)!

@Test("Une réponse valide donne les deux pourcentages")
func decodesValidPayload() throws {
    let snapshot = try UsageResponseDecoder.decode(validPayload)
    #expect(snapshot.fiveHour.utilization == 10.0)
    #expect(snapshot.sevenDay.utilization == 2.5)
}

@Test("Les dates de remise à zéro sont décodées")
func decodesResetDates() throws {
    let snapshot = try UsageResponseDecoder.decode(validPayload)
    let expected = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2026, month: 9, day: 22, hour: 11, minute: 30
    ).date!
    let actual = try #require(snapshot.fiveHour.resetsAt)
    #expect(abs(actual.timeIntervalSince(expected)) < 1)
}

@Test("Une date absente devient nil sans échouer")
func decodesMissingResetDate() throws {
    let payload = """
    {"five_hour": {"utilization": 0.0, "resets_at": null},
     "seven_day": {"utilization": 0.0, "resets_at": null}}
    """.data(using: .utf8)!
    let snapshot = try UsageResponseDecoder.decode(payload)
    #expect(snapshot.fiveHour.resetsAt == nil)
    #expect(snapshot.sevenDay.resetsAt == nil)
}

@Test("Un JSON sans les champs attendus produit malformedResponse")
func rejectsMissingFields() {
    let payload = #"{"seven_day": {"utilization": 2.0}}"#.data(using: .utf8)!
    #expect(throws: UsageError.malformedResponse) {
        try UsageResponseDecoder.decode(payload)
    }
}

@Test("Un contenu illisible produit malformedResponse")
func rejectsGarbage() {
    let payload = "pas du json".data(using: .utf8)!
    #expect(throws: UsageError.malformedResponse) {
        try UsageResponseDecoder.decode(payload)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier l'échec**

Run: `swift test`
Expected: échec de compilation, « cannot find 'UsageResponseDecoder' in scope ».

- [ ] **Step 3: Écrire le décodeur**

Créer `Sources/ClaudeUsage/UsageResponseDecoder.swift` :

```swift
import Foundation

/// Transforme la réponse JSON de l'API d'utilisation en `UsageSnapshot`.
///
/// La réponse réelle contient de nombreux champs facultatifs ; seuls
/// `five_hour` et `seven_day` sont lus, tout le reste est ignoré.
enum UsageResponseDecoder {

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

    /// Analyseur des dates ISO 8601 avec fraction de seconde.
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Analyseur de secours pour les dates sans fraction de seconde.
    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Décode les données brutes de l'API.
    /// - Throws: `UsageError.malformedResponse` si la forme attendue est absente.
    static func decode(_ data: Data) throws -> UsageSnapshot {
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
    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractionalFormatter.date(from: value) ?? plainFormatter.date(from: value)
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier le succès**

Run: `swift test`
Expected: les cinq tests de décodage passent, ainsi que ceux de la tâche 1.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeUsage/UsageResponseDecoder.swift Tests/ClaudeUsageTests/UsageResponseDecoderTests.swift
git commit -m "feat: décodage de la réponse d'utilisation"
```

---

### Task 3: Mise en forme de l'affichage

**Files:**
- Create: `Sources/ClaudeUsage/UsageFormatter.swift`
- Test: `Tests/ClaudeUsageTests/UsageFormatterTests.swift`

**Interfaces:**
- Consumes: `UsageSnapshot`, `UsageLimit`, `UsageError` (tâche 1).
- Produces: `enum UsageFormatter` avec :
  - `static func statusText(for snapshot: UsageSnapshot) -> String`
  - `static let placeholderText: String` (vaut `"—"`)
  - `static func statusColor(for snapshot: UsageSnapshot) -> NSColor`
  - `static func percentText(_ utilization: Double) -> String`
  - `static func resetText(for date: Date?) -> String?`
  - `static func message(for error: UsageError) -> String`

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/ClaudeUsageTests/UsageFormatterTests.swift` :

```swift
import Testing
import Foundation
import AppKit
@testable import ClaudeUsage

private func snapshot(fiveHour: Double, sevenDay: Double) -> UsageSnapshot {
    UsageSnapshot(
        fiveHour: UsageLimit(utilization: fiveHour, resetsAt: nil),
        sevenDay: UsageLimit(utilization: sevenDay, resetsAt: nil)
    )
}

@Test("Le texte de la barre montre les deux pourcentages séparés par un point médian")
func statusTextFormat() {
    #expect(UsageFormatter.statusText(for: snapshot(fiveHour: 10, sevenDay: 2)) == "10% · 2%")
}

@Test("Les pourcentages sont arrondis à l'entier le plus proche")
func statusTextRounding() {
    #expect(UsageFormatter.statusText(for: snapshot(fiveHour: 10.4, sevenDay: 2.5)) == "10% · 3%")
    #expect(UsageFormatter.percentText(0) == "0%")
    #expect(UsageFormatter.percentText(99.9) == "100%")
}

@Test("En dessous de 70 % la couleur reste celle du système")
func colorBelowWarning() {
    #expect(UsageFormatter.statusColor(for: snapshot(fiveHour: 69, sevenDay: 0)) == .labelColor)
}

@Test("À partir de 70 % la couleur passe à l'orange")
func colorAtWarning() {
    #expect(UsageFormatter.statusColor(for: snapshot(fiveHour: 70, sevenDay: 0)) == .systemOrange)
    #expect(UsageFormatter.statusColor(for: snapshot(fiveHour: 0, sevenDay: 89)) == .systemOrange)
}

@Test("À partir de 90 % la couleur passe au rouge")
func colorAtCritical() {
    #expect(UsageFormatter.statusColor(for: snapshot(fiveHour: 0, sevenDay: 90)) == .systemRed)
}

@Test("La couleur suit la plus élevée des deux limites")
func colorUsesHigherLimit() {
    #expect(UsageFormatter.statusColor(for: snapshot(fiveHour: 95, sevenDay: 3)) == .systemRed)
}

@Test("Une date de remise à zéro devient une phrase lisible")
func resetTextPresent() throws {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let text = try #require(UsageFormatter.resetText(for: date))
    #expect(text.hasPrefix("Réinitialisation à "))
}

@Test("Une date absente ne produit aucun texte")
func resetTextAbsent() {
    #expect(UsageFormatter.resetText(for: nil) == nil)
}

@Test("Chaque erreur a son propre message en français")
func errorMessages() {
    #expect(UsageFormatter.message(for: .credentialsNotFound).contains("Claude Code"))
    #expect(UsageFormatter.message(for: .sessionExpired).contains("Claude Code"))
    #expect(!UsageFormatter.message(for: .network("timeout")).isEmpty)
    #expect(!UsageFormatter.message(for: .malformedResponse).isEmpty)
}

@Test("Le texte de repli est un tiret cadratin")
func placeholder() {
    #expect(UsageFormatter.placeholderText == "—")
}
```

- [ ] **Step 2: Lancer les tests pour vérifier l'échec**

Run: `swift test`
Expected: échec de compilation, « cannot find 'UsageFormatter' in scope ».

- [ ] **Step 3: Écrire le formateur**

Créer `Sources/ClaudeUsage/UsageFormatter.swift` :

```swift
import Foundation
import AppKit

/// Met en forme un instantané d'utilisation pour l'affichage.
///
/// Fonctions pures : aucun accès au réseau, au disque ni à l'horloge,
/// ce qui les rend directement testables.
enum UsageFormatter {

    /// Seuil à partir duquel l'affichage passe en orange.
    private static let warningThreshold: Double = 70
    /// Seuil à partir duquel l'affichage passe en rouge.
    private static let criticalThreshold: Double = 90

    /// Texte affiché tant qu'aucune donnée n'a pu être récupérée.
    static let placeholderText = "—"

    /// Texte de la barre de menus : limite 5 h puis limite hebdomadaire.
    static func statusText(for snapshot: UsageSnapshot) -> String {
        "\(percentText(snapshot.fiveHour.utilization)) · \(percentText(snapshot.sevenDay.utilization))"
    }

    /// Un pourcentage arrondi à l'entier, suivi du signe pour cent.
    static func percentText(_ utilization: Double) -> String {
        "\(Int(utilization.rounded()))%"
    }

    /// Couleur du texte, déterminée par la plus chargée des deux limites.
    static func statusColor(for snapshot: UsageSnapshot) -> NSColor {
        let highest = max(snapshot.fiveHour.utilization, snapshot.sevenDay.utilization)
        if highest >= criticalThreshold { return .systemRed }
        if highest >= warningThreshold { return .systemOrange }
        return .labelColor
    }

    /// Phrase indiquant l'heure locale de remise à zéro, ou rien si elle est inconnue.
    static func resetText(for date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Réinitialisation à \(formatter.string(from: date))"
    }

    /// Message affiché dans le menu lorsqu'une récupération a échoué.
    static func message(for error: UsageError) -> String {
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
```

- [ ] **Step 4: Lancer les tests pour vérifier le succès**

Run: `swift test`
Expected: tous les tests passent.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeUsage/UsageFormatter.swift Tests/ClaudeUsageTests/UsageFormatterTests.swift
git commit -m "feat: mise en forme de l'affichage d'utilisation"
```

---

### Task 4: Lecture du jeton dans le trousseau

**Files:**
- Create: `Sources/ClaudeUsage/CredentialStore.swift`
- Test: `Tests/ClaudeUsageTests/CredentialStoreTests.swift`

**Interfaces:**
- Consumes: `UsageError` (tâche 1).
- Produces:
  - `protocol CredentialProviding: Sendable { func accessToken() throws -> String }`
  - `struct KeychainCredentialStore: CredentialProviding` avec `init()`
  - `enum CredentialPayloadDecoder { static func accessToken(from data: Data) throws -> String }`

Note pour l'implémenteur : le trousseau ne peut pas être testé automatiquement, il ouvre une boîte de dialogue système. Seul le décodage du JSON stocké est testé ; `KeychainCredentialStore` se contente d'appeler `SecItemCopyMatching` puis `CredentialPayloadDecoder`.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/ClaudeUsageTests/CredentialStoreTests.swift` :

```swift
import Testing
import Foundation
@testable import ClaudeUsage

@Test("Le jeton est extrait du JSON du trousseau")
func extractsAccessToken() throws {
    let payload = #"{"claudeAiOauth": {"accessToken": "abc123", "refreshToken": "xyz"}}"#
        .data(using: .utf8)!
    #expect(try CredentialPayloadDecoder.accessToken(from: payload) == "abc123")
}

@Test("Un JSON sans jeton produit credentialsNotFound")
func rejectsPayloadWithoutToken() {
    let payload = #"{"claudeAiOauth": {"refreshToken": "xyz"}}"#.data(using: .utf8)!
    #expect(throws: UsageError.credentialsNotFound) {
        try CredentialPayloadDecoder.accessToken(from: payload)
    }
}

@Test("Un jeton vide est refusé")
func rejectsEmptyToken() {
    let payload = #"{"claudeAiOauth": {"accessToken": ""}}"#.data(using: .utf8)!
    #expect(throws: UsageError.credentialsNotFound) {
        try CredentialPayloadDecoder.accessToken(from: payload)
    }
}

@Test("Un contenu illisible produit credentialsNotFound")
func rejectsGarbagePayload() {
    let payload = "pas du json".data(using: .utf8)!
    #expect(throws: UsageError.credentialsNotFound) {
        try CredentialPayloadDecoder.accessToken(from: payload)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier l'échec**

Run: `swift test`
Expected: échec de compilation, « cannot find 'CredentialPayloadDecoder' in scope ».

- [ ] **Step 3: Écrire le magasin d'identifiants**

Créer `Sources/ClaudeUsage/CredentialStore.swift` :

```swift
import Foundation
import Security

/// Fournit le jeton d'accès nécessaire à l'appel de l'API.
protocol CredentialProviding: Sendable {
    /// Renvoie le jeton d'accès courant.
    /// - Throws: `UsageError.credentialsNotFound` s'il est absent ou illisible.
    func accessToken() throws -> String
}

/// Décode le contenu JSON enregistré par Claude Code dans le trousseau.
enum CredentialPayloadDecoder {

    /// Forme du secret stocké par Claude Code.
    private struct Payload: Decodable {
        struct OAuth: Decodable {
            let accessToken: String?
        }
        let claudeAiOauth: OAuth
    }

    /// Extrait le jeton d'accès du secret brut.
    /// - Throws: `UsageError.credentialsNotFound` si le jeton est absent ou vide.
    static func accessToken(from data: Data) throws -> String {
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
struct KeychainCredentialStore: CredentialProviding {

    /// Nom du service sous lequel Claude Code range ses identifiants.
    private let service = "Claude Code-credentials"

    func accessToken() throws -> String {
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
```

- [ ] **Step 4: Lancer les tests pour vérifier le succès**

Run: `swift test`
Expected: tous les tests passent.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeUsage/CredentialStore.swift Tests/ClaudeUsageTests/CredentialStoreTests.swift
git commit -m "feat: lecture du jeton dans le trousseau"
```

---

### Task 5: Client de l'API d'utilisation

**Files:**
- Create: `Sources/ClaudeUsage/UsageClient.swift`
- Test: `Tests/ClaudeUsageTests/UsageClientTests.swift`

**Interfaces:**
- Consumes: `CredentialProviding` (tâche 4), `UsageResponseDecoder` (tâche 2), `UsageSnapshot` et `UsageError` (tâche 1).
- Produces:
  - `protocol UsageFetching: Sendable { func fetch() async throws -> UsageSnapshot }`
  - `protocol HTTPTransporting: Sendable { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }`
  - `struct URLSessionTransport: HTTPTransporting` avec `init(session: URLSession = .shared)`
  - `struct APIUsageClient: UsageFetching` avec `init(credentials: CredentialProviding, transport: HTTPTransporting)`

Note pour l'implémenteur : le transport est un protocole pour que le test injecte une réponse sans réseau. Un code HTTP 401 ou 403 doit devenir `UsageError.sessionExpired`, tout autre code hors 200-299 devient `UsageError.network`.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/ClaudeUsageTests/UsageClientTests.swift` :

```swift
import Testing
import Foundation
@testable import ClaudeUsage

/// Doublure renvoyant un jeton fixe, ou une erreur si on le lui demande.
private struct StubCredentials: CredentialProviding {
    var token: String? = "test-token"
    func accessToken() throws -> String {
        guard let token else { throw UsageError.credentialsNotFound }
        return token
    }
}

/// Doublure de transport : enregistre la requête reçue et rejoue une réponse fixée.
private final class StubTransport: HTTPTransporting, @unchecked Sendable {
    var statusCode = 200
    var body = Data()
    var thrownError: Error?
    private(set) var lastRequest: URLRequest?

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        if let thrownError { throw thrownError }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil
        )!
        return (body, response)
    }
}

private let samplePayload = """
{"five_hour": {"utilization": 42.0, "resets_at": null},
 "seven_day": {"utilization": 7.0, "resets_at": null}}
""".data(using: .utf8)!

@Test("Une réponse réussie donne l'instantané décodé")
func fetchesSnapshot() async throws {
    let transport = StubTransport()
    transport.body = samplePayload
    let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
    let snapshot = try await client.fetch()
    #expect(snapshot.fiveHour.utilization == 42.0)
    #expect(snapshot.sevenDay.utilization == 7.0)
}

@Test("La requête porte l'adresse et les en-têtes attendus")
func buildsExpectedRequest() async throws {
    let transport = StubTransport()
    transport.body = samplePayload
    let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
    _ = try await client.fetch()
    let request = try #require(transport.lastRequest)
    #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
}

@Test("Un jeton absent remonte credentialsNotFound sans appeler le réseau")
func propagatesMissingCredentials() async {
    let transport = StubTransport()
    let client = APIUsageClient(credentials: StubCredentials(token: nil), transport: transport)
    await #expect(throws: UsageError.credentialsNotFound) { try await client.fetch() }
    #expect(transport.lastRequest == nil)
}

@Test("Un code 401 devient sessionExpired")
func mapsUnauthorized() async {
    let transport = StubTransport()
    transport.statusCode = 401
    let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
    await #expect(throws: UsageError.sessionExpired) { try await client.fetch() }
}

@Test("Un code 500 devient une erreur réseau")
func mapsServerError() async {
    let transport = StubTransport()
    transport.statusCode = 500
    let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
    await #expect(throws: UsageError.network("code 500")) { try await client.fetch() }
}

@Test("Une panne de transport devient une erreur réseau")
func mapsTransportFailure() async {
    let transport = StubTransport()
    transport.thrownError = URLError(.notConnectedToInternet)
    let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
    await #expect(throws: UsageError.self) { try await client.fetch() }
}

@Test("Un corps illisible devient malformedResponse")
func mapsBadBody() async {
    let transport = StubTransport()
    transport.body = "pas du json".data(using: .utf8)!
    let client = APIUsageClient(credentials: StubCredentials(), transport: transport)
    await #expect(throws: UsageError.malformedResponse) { try await client.fetch() }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier l'échec**

Run: `swift test`
Expected: échec de compilation, « cannot find 'APIUsageClient' in scope ».

- [ ] **Step 3: Écrire le client**

Créer `Sources/ClaudeUsage/UsageClient.swift` :

```swift
import Foundation

/// Récupère l'utilisation courante du plan.
protocol UsageFetching: Sendable {
    /// Interroge la source de données et renvoie un instantané.
    func fetch() async throws -> UsageSnapshot
}

/// Exécute une requête HTTP. Extrait en protocole pour rester testable sans réseau.
protocol HTTPTransporting: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Transport réel, adossé à `URLSession`.
struct URLSessionTransport: HTTPTransporting {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.malformedResponse
        }
        return (data, http)
    }
}

/// Interroge l'API d'utilisation d'Anthropic avec le jeton de la session Claude Code.
struct APIUsageClient: UsageFetching {

    /// Adresse du point d'accès renvoyant l'utilisation du plan.
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let credentials: CredentialProviding
    private let transport: HTTPTransporting

    init(credentials: CredentialProviding, transport: HTTPTransporting) {
        self.credentials = credentials
        self.transport = transport
    }

    func fetch() async throws -> UsageSnapshot {
        // Le jeton est lu à chaque appel : il n'est jamais conservé entre deux requêtes.
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
            throw UsageError.sessionExpired
        default:
            throw UsageError.network("code \(response.statusCode)")
        }
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier le succès**

Run: `swift test`
Expected: tous les tests passent.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeUsage/UsageClient.swift Tests/ClaudeUsageTests/UsageClientTests.swift
git commit -m "feat: client de l'API d'utilisation"
```

---

### Task 6: Contrôleur de la barre de menus et point d'entrée

**Files:**
- Create: `Sources/ClaudeUsage/MenuBarController.swift`
- Create: `Sources/ClaudeUsage/main.swift`

**Interfaces:**
- Consumes: `UsageFetching`, `APIUsageClient`, `URLSessionTransport` (tâche 5), `KeychainCredentialStore` (tâche 4), `UsageFormatter` (tâche 3), `UsageSnapshot` et `UsageError` (tâche 1).
- Produces: `@MainActor final class MenuBarController: NSObject` avec `init(client: UsageFetching)` et `func start()`.

Note pour l'implémenteur : cette tâche n'a pas de test automatisé, l'interface AppKit ne se teste pas sans session graphique. Elle se vérifie en lançant l'application et en regardant la barre de menus. Toute la logique testable a déjà été écrite dans les tâches précédentes.

- [ ] **Step 1: Écrire le contrôleur**

Créer `Sources/ClaudeUsage/MenuBarController.swift` :

```swift
import AppKit

/// Gère l'élément de barre de menus : affichage, menu déroulant et rafraîchissement.
@MainActor
final class MenuBarController: NSObject {

    /// Intervalle entre deux interrogations de l'API, en secondes.
    private static let refreshInterval: TimeInterval = 60

    private let client: UsageFetching
    private let statusItem: NSStatusItem
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    init(client: UsageFetching) {
        self.client = client
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
    }

    /// Affiche l'élément, lance une première récupération et démarre le minuteur.
    func start() {
        statusItem.button?.title = UsageFormatter.placeholderText
        showLoadingMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Lance une récupération, en annulant celle qui serait encore en cours.
    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.client.fetch()
                self.apply(snapshot)
            } catch let error as UsageError {
                self.apply(error)
            } catch {
                self.apply(UsageError.network(error.localizedDescription))
            }
        }
    }

    /// Met à jour la barre et le menu avec des données fraîches.
    private func apply(_ snapshot: UsageSnapshot) {
        statusItem.button?.attributedTitle = NSAttributedString(
            string: UsageFormatter.statusText(for: snapshot),
            attributes: [
                .foregroundColor: UsageFormatter.statusColor(for: snapshot),
                .font: NSFont.menuBarFont(ofSize: 0),
            ]
        )
        let menu = makeMenu()
        appendLimit(to: menu, title: "Limite 5 h", limit: snapshot.fiveHour)
        appendLimit(to: menu, title: "Limite hebdomadaire", limit: snapshot.sevenDay)
        appendActions(to: menu)
        statusItem.menu = menu
    }

    /// Conserve le dernier affichage connu et explique l'échec dans le menu.
    private func apply(_ error: UsageError) {
        if statusItem.button?.title.isEmpty ?? true {
            statusItem.button?.title = UsageFormatter.placeholderText
        }
        let menu = makeMenu()
        let item = NSMenuItem(title: UsageFormatter.message(for: error), action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        appendActions(to: menu)
        statusItem.menu = menu
    }

    /// Menu affiché avant la toute première réponse.
    private func showLoadingMenu() {
        let menu = makeMenu()
        let item = NSMenuItem(title: "Chargement…", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        appendActions(to: menu)
        statusItem.menu = menu
    }

    /// Ajoute une limite au menu, avec sa ligne de remise à zéro si elle est connue.
    private func appendLimit(to menu: NSMenu, title: String, limit: UsageLimit) {
        let item = NSMenuItem(
            title: "\(title) — \(UsageFormatter.percentText(limit.utilization))",
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = false
        menu.addItem(item)

        if let reset = UsageFormatter.resetText(for: limit.resetsAt) {
            let subtitle = NSMenuItem(title: reset, action: nil, keyEquivalent: "")
            subtitle.isEnabled = false
            subtitle.attributedTitle = NSAttributedString(
                string: reset,
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                ]
            )
            menu.addItem(subtitle)
        }
    }

    /// Crée un menu dont l'activation des entrées est pilotée à la main.
    /// Sans cela, AppKit réactive tout seul les lignes purement informatives.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }

    /// Ajoute le séparateur puis les deux commandes communes à tous les menus.
    private func appendActions(to menu: NSMenu) {
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Rafraîchir maintenant", action: #selector(refreshNow), keyEquivalent: "r")
        )
        menu.addItem(
            NSMenuItem(title: "Quitter", action: #selector(quit), keyEquivalent: "q")
        )
        for item in menu.items where item.action != nil {
            item.target = self
        }
    }

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
```

- [ ] **Step 2: Écrire le point d'entrée**

Créer `Sources/ClaudeUsage/main.swift` :

```swift
import AppKit

// Point d'entrée : assemble les composants et démarre la boucle d'événements.
// `.accessory` garde l'application hors du Dock et du sélecteur d'applications.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let client = APIUsageClient(
    credentials: KeychainCredentialStore(),
    transport: URLSessionTransport()
)
let controller = MenuBarController(client: client)
controller.start()

application.run()
```

- [ ] **Step 3: Compiler et lancer**

Run: `swift build && .build/debug/ClaudeUsage`
Expected: deux pourcentages apparaissent dans la barre de menus ; le clic ouvre le menu avec les heures de réinitialisation, « Rafraîchir maintenant » et « Quitter ». Quitter l'application avec cette entrée de menu.

Si le trousseau demande une autorisation, l'accorder. Si la barre affiche `—`, ouvrir le menu pour lire le message d'erreur.

- [ ] **Step 4: Vérifier que les tests passent toujours**

Run: `swift test`
Expected: tous les tests des tâches 1 à 5 passent.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeUsage/MenuBarController.swift Sources/ClaudeUsage/main.swift
git commit -m "feat: barre de menus et point d'entrée"
```

---

### Task 7: Script de construction du bundle et documentation

**Files:**
- Create: `build.sh`
- Create: `Resources/Info.plist`
- Create: `README.md`

**Interfaces:**
- Consumes: la cible exécutable `ClaudeUsage` (tâche 1).
- Produces: `build/ClaudeUsage.app`, un bundle lançable par double-clic.

- [ ] **Step 1: Écrire l'`Info.plist`**

Créer `Resources/Info.plist` :

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ClaudeUsage</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Usage</string>
    <key>CFBundleIdentifier</key>
    <string>fr.gkfa.claudeusage</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeUsage</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Écrire `build.sh`**

```bash
#!/bin/bash
# Compile l'application et fabrique le bundle ClaudeUsage.app dans build/.
# Option --install : copie ensuite le bundle dans /Applications.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeUsage"
BUNDLE="build/${APP_NAME}.app"

echo "Compilation en mode release…"
swift build -c release

echo "Fabrication du bundle…"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp ".build/release/${APP_NAME}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"

# Signature locale : sans elle, le trousseau redemande l'autorisation à chaque
# reconstruction, car l'identité de l'application change.
codesign --force --deep --sign - "$BUNDLE"

echo "Bundle prêt : ${BUNDLE}"

if [[ "${1:-}" == "--install" ]]; then
    echo "Installation dans /Applications…"
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$BUNDLE" /Applications/
    echo "Installé : /Applications/${APP_NAME}.app"
fi
```

Puis le rendre exécutable :

```bash
chmod +x build.sh
```

- [ ] **Step 3: Lancer la construction et vérifier le bundle**

Run: `./build.sh && open build/ClaudeUsage.app`
Expected: le script se termine sans erreur et les pourcentages apparaissent dans la barre de menus, sans icône dans le Dock. Quitter ensuite via le menu.

- [ ] **Step 4: Écrire le `README.md`**

```markdown
# Claude Usage

Un petit indicateur dans la barre de menus de macOS qui montre en
permanence deux pourcentages : l'utilisation de la limite glissante de
cinq heures et celle de la limite hebdomadaire du plan Claude.

    10% · 2%

Le premier nombre est la limite 5 heures, le second la limite
hebdomadaire. Le texte passe en orange à partir de 70 % et en rouge à
partir de 90 %.

## Installation

    ./build.sh --install

L'application arrive dans `/Applications`. Sans `--install`, le bundle
reste dans `build/`.

Au premier lancement, macOS demande l'autorisation d'accéder au
trousseau : il faut l'accorder pour que l'application puisse lire la
session ouverte par Claude Code.

## Lancement automatique au démarrage

Réglages Système → Général → Ouverture et extensions → Ouvrir au
démarrage, puis ajouter `ClaudeUsage.app`.

## Fonctionnement

L'application réutilise la session déjà ouverte par Claude Code : elle
lit le jeton dans le trousseau macOS, puis interroge l'API
d'utilisation d'Anthropic une fois par minute. Aucun identifiant n'est
enregistré par l'application, et rien n'est écrit sur le disque.

Si la barre affiche un tiret, ouvrir le menu : il explique ce qui ne va
pas. Dans la plupart des cas, il suffit de relancer Claude Code pour
renouveler la session.

## Développement

    swift build     # compiler
    swift test      # lancer les tests
    swift run       # lancer sans fabriquer de bundle

Le code et les noms sont en anglais, les commentaires et la
documentation en français.
```

- [ ] **Step 5: Commit**

```bash
git add build.sh Resources/Info.plist README.md
git commit -m "feat: script de construction du bundle et documentation"
```
