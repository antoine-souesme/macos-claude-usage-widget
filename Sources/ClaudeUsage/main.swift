import AppKit
import ClaudeUsageCore

// Point d'entrée : assemble les composants et démarre la boucle d'événements.
// La politique « accessory » garde l'application hors du Dock et du sélecteur
// d'applications : elle n'existe que dans la barre de menus.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let client = APIUsageClient(
    credentials: CachedCredentialStore(source: KeychainCredentialStore()),
    transport: URLSessionTransport()
)
let controller = MenuBarController(client: client)
controller.start()

application.run()
