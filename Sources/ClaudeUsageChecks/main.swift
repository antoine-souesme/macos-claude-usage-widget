import Foundation

// Point d'entrée des vérifications : enchaîne les familles de cas puis
// affiche le bilan. Le tout vit dans une fonction pour garder le compteur
// local, une variable globale étant isolée à l'acteur principal.
func runAllChecks() async -> Never {
    var runner = CheckRunner()
    runModelChecks(&runner)
    runDecoderChecks(&runner)
    runFormatterChecks(&runner)
    runBackoffChecks(&runner)
    runCredentialChecks(&runner)
    await runClientChecks(&runner)
    runner.finish()
}

await runAllChecks()
