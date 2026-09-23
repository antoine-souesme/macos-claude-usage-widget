import AppKit
import Foundation

/// Gère l'élément de barre de menus : affichage, menu déroulant et rafraîchissement.
@MainActor
public final class MenuBarController: NSObject {

    /// Intervalle entre deux interrogations de l'API, en secondes.
    private static let refreshInterval: TimeInterval = 120

    private let client: UsageFetching
    private let statusItem: NSStatusItem
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    /// Décide de l'attente à observer quand l'API refuse les requêtes.
    private var retryPolicy = RetryPolicy()
    /// Instant avant lequel aucune requête ne doit partir, pendant un ralentissement.
    private var nextAllowedFetch: Date?

    public init(client: UsageFetching) {
        self.client = client
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
    }

    /// Affiche l'élément, lance une première récupération et démarre le minuteur.
    public func start() {
        statusItem.button?.title = UsageFormatter.placeholderText
        showLoadingMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Lance une récupération, en annulant celle qui serait encore en cours.
    ///
    /// Pendant un ralentissement, la requête est retenue : insister ne ferait
    /// que prolonger le refus du serveur.
    private func refresh() {
        if let nextAllowedFetch, Date() < nextAllowedFetch {
            showRateLimit(retryIn: nextAllowedFetch.timeIntervalSinceNow)
            return
        }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.client.fetch()
                self.retryPolicy.reset()
                self.nextAllowedFetch = nil
                self.apply(snapshot)
            } catch UsageError.rateLimited(let retryAfter) {
                let delay = self.retryPolicy.delayAfterRateLimit(retryAfter: retryAfter)
                self.nextAllowedFetch = Date().addingTimeInterval(delay)
                self.showRateLimit(retryIn: delay)
            } catch let error as UsageError {
                self.apply(error)
            } catch {
                self.apply(UsageError.network(error.localizedDescription))
            }
        }
    }

    /// Met à jour la barre et le menu avec des données fraîches.
    private func apply(_ snapshot: UsageSnapshot) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 0)
        ]
        if let color = UsageFormatter.statusColor(for: snapshot) {
            attributes[.foregroundColor] = color
        }
        statusItem.button?.attributedTitle = NSAttributedString(
            string: UsageFormatter.statusText(for: snapshot),
            attributes: attributes
        )
        let menu = makeMenu()
        appendLimit(to: menu, title: "5-hour limit", limit: snapshot.fiveHour)
        appendLimit(to: menu, title: "Weekly limit", limit: snapshot.sevenDay)
        appendActions(to: menu)
        statusItem.menu = menu
    }

    /// Conserve le dernier affichage connu et explique l'échec dans le menu.
    private func apply(_ error: UsageError) {
        if statusItem.button?.title.isEmpty ?? true {
            statusItem.button?.title = UsageFormatter.placeholderText
        }
        let menu = makeMenu()
        appendInfo(to: menu, text: UsageFormatter.message(for: error))
        appendActions(to: menu)
        statusItem.menu = menu
    }

    /// Explique le ralentissement en cours et le moment du prochain essai.
    private func showRateLimit(retryIn: TimeInterval) {
        if statusItem.button?.title.isEmpty ?? true {
            statusItem.button?.title = UsageFormatter.placeholderText
        }
        let menu = makeMenu()
        appendInfo(
            to: menu,
            text: UsageFormatter.message(for: .rateLimited(retryAfter: nil), retryIn: retryIn)
        )
        appendActions(to: menu)
        statusItem.menu = menu
    }

    /// Menu affiché avant la toute première réponse.
    private func showLoadingMenu() {
        let menu = makeMenu()
        appendInfo(to: menu, text: "Loading…")
        appendActions(to: menu)
        statusItem.menu = menu
    }

    /// Crée un menu dont l'activation des entrées est pilotée à la main.
    /// Sans cela, AppKit réactive tout seul les lignes purement informatives.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }

    /// Ajoute une ligne d'information, non cliquable.
    private func appendInfo(to menu: NSMenu, text: String) {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    /// Ajoute une limite au menu, avec sa ligne de remise à zéro si elle est connue.
    private func appendLimit(to menu: NSMenu, title: String, limit: UsageLimit) {
        appendInfo(to: menu, text: "\(title): \(UsageFormatter.percentText(limit.utilization))")

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

    /// Ajoute le séparateur puis les deux commandes communes à tous les menus.
    private func appendActions(to menu: NSMenu) {
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(
            title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
