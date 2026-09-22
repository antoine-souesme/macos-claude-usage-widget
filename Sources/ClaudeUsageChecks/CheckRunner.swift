import Foundation

/// Harnais de vérification minimal, en remplacement de XCTest.
///
/// Xcode n'étant pas installé sur la machine de développement, ni XCTest ni
/// Swift Testing ne sont disponibles. Ce petit exécutable joue le même rôle :
/// il enchaîne des cas, affiche les échecs et renvoie un code de sortie non nul
/// si l'un d'eux tombe.
struct CheckRunner {

    private var passed = 0
    private var failures: [String] = []

    /// Exécute un cas ; `body` signale un échec en levant une erreur ou en
    /// renvoyant `false` via `expect`.
    mutating func check(_ name: String, _ body: (inout Assertions) throws -> Void) {
        var assertions = Assertions(caseName: name)
        do {
            try body(&assertions)
        } catch {
            assertions.record("erreur inattendue : \(error)")
        }
        if assertions.failures.isEmpty {
            passed += 1
        } else {
            failures.append(contentsOf: assertions.failures)
        }
    }

    /// Variante asynchrone de `check`.
    mutating func checkAsync(_ name: String, _ body: (inout Assertions) async throws -> Void) async {
        var assertions = Assertions(caseName: name)
        do {
            try await body(&assertions)
        } catch {
            assertions.record("erreur inattendue : \(error)")
        }
        if assertions.failures.isEmpty {
            passed += 1
        } else {
            failures.append(contentsOf: assertions.failures)
        }
    }

    /// Affiche le bilan et termine le programme avec le code qui convient.
    func finish() -> Never {
        if failures.isEmpty {
            print("✅ \(passed) vérifications passées")
            exit(0)
        }
        for failure in failures {
            print("❌ \(failure)")
        }
        print("\(passed) passées, \(failures.count) échecs")
        exit(1)
    }
}

/// Collecte les échecs d'un cas de vérification.
struct Assertions {
    let caseName: String
    private(set) var failures: [String] = []

    init(caseName: String) {
        self.caseName = caseName
    }

    /// Enregistre un échec décrit librement.
    mutating func record(_ message: String) {
        failures.append("\(caseName) : \(message)")
    }

    /// Vérifie qu'une condition est vraie.
    mutating func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition { record(message()) }
    }

    /// Vérifie une égalité et décrit l'écart en cas d'échec.
    mutating func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String = "") {
        if actual != expected {
            let prefix = label.isEmpty ? "" : "\(label) : "
            record("\(prefix)attendu \(expected), obtenu \(actual)")
        }
    }

    /// Vérifie qu'une valeur facultative est présente et la renvoie.
    mutating func require<T>(_ value: T?, _ label: String) -> T? {
        if value == nil { record("\(label) est absent") }
        return value
    }

    /// Vérifie que `body` lève exactement l'erreur attendue.
    mutating func expectThrows<E: Error & Equatable>(_ expected: E, _ body: () throws -> Void) {
        do {
            try body()
            record("aucune erreur levée, \(expected) attendue")
        } catch let error as E where error == expected {
            return
        } catch {
            record("erreur \(error) levée, \(expected) attendue")
        }
    }

    /// Variante asynchrone de `expectThrows`.
    mutating func expectThrowsAsync<E: Error & Equatable>(
        _ expected: E, _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            record("aucune erreur levée, \(expected) attendue")
        } catch let error as E where error == expected {
            return
        } catch {
            record("erreur \(error) levée, \(expected) attendue")
        }
    }
}
