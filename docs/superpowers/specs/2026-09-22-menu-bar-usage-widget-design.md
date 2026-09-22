# Widget barre de menus — suivi de l'utilisation du plan Claude

Date : 2026-09-22

## Objectif

Afficher en permanence, dans la barre de menus de macOS, deux
pourcentages d'utilisation du plan Claude : la limite glissante de 5
heures et la limite hebdomadaire. Aucune fenêtre, aucune icône dans le
Dock.

## Critères de réussite

- Les deux pourcentages sont visibles sans aucune action de
  l'utilisateur.
- Les valeurs correspondent à celles affichées par la commande
  `/usage` de Claude Code.
- L'application ne stocke aucun identifiant et ne demande aucune
  configuration.
- Elle consomme des ressources négligeables (un appel réseau par
  minute).

## Source des données

L'application réutilise la session déjà ouverte par Claude Code.

1. Lecture du trousseau macOS : élément générique dont le service est
   `Claude Code-credentials`. Sa valeur est du JSON ; le jeton se
   trouve dans `claudeAiOauth.accessToken`.
2. Appel `GET https://api.anthropic.com/api/oauth/usage` avec les
   en-têtes `Authorization: Bearer <jeton>` et
   `anthropic-beta: oauth-2025-04-20`.
3. La réponse contient les champs `five_hour` et `seven_day`, chacun
   avec `utilization` (nombre, en pourcentage) et `resets_at` (date
   ISO 8601). Tous les autres champs sont ignorés.

Aucun jeton n'est écrit sur le disque ni conservé en mémoire au-delà
de la requête en cours.

## Affichage dans la barre de menus

Format : `10% · 2%` — d'abord la limite 5 heures, puis
l'hebdomadaire, séparées par un point médian.

Les pourcentages sont arrondis à l'entier le plus proche.

Couleur du texte, déterminée par la plus élevée des deux valeurs :

- moins de 70 % : couleur par défaut du système ;
- de 70 % à moins de 90 % : orange ;
- 90 % et plus : rouge.

En cas d'échec (jeton absent, jeton expiré, réseau indisponible),
la barre affiche `—` et conserve cet affichage jusqu'au prochain
succès.

## Menu déroulant

Au clic, un menu affiche :

- « Limite 5 h — 10 % » puis, en sous-titre grisé, l'heure de remise à
  zéro au format local (par exemple « Réinitialisation à 13:30 ») ;
- « Limite hebdomadaire — 2 % » avec la même sous-ligne ;
- un séparateur ;
- « Rafraîchir maintenant » ;
- « Quitter ».

En cas d'erreur, les deux premières entrées sont remplacées par une
ligne expliquant le problème : jeton introuvable, session expirée, ou
échec réseau. Pour les deux premiers cas, le message invite à relancer
Claude Code.

## Rafraîchissement

Un `Timer` déclenche une requête toutes les 60 secondes, ainsi qu'une
fois au lancement. L'entrée « Rafraîchir maintenant » déclenche la même
requête immédiatement. Les appels réseau sont asynchrones ; l'interface
n'est jamais bloquée.

## Architecture

Cinq fichiers sources, chacun avec une responsabilité unique.

### `CredentialStore.swift`

Protocole `CredentialProviding` avec une seule méthode renvoyant le
jeton d'accès ou une erreur. Implémentation `KeychainCredentialStore`
qui lit le trousseau via l'API Security et décode le JSON.

Dépend de : Foundation, Security.

### `UsageClient.swift`

Protocole `UsageFetching` renvoyant un `UsageSnapshot`. Implémentation
`APIUsageClient` qui construit la requête, l'exécute et décode la
réponse. Prend un `CredentialProviding` et un `URLSession` par
injection.

Types de données : `UsageSnapshot` (deux `UsageLimit`), `UsageLimit`
(`utilization: Double`, `resetsAt: Date`), et `UsageError` énumérant
les cas d'échec.

Dépend de : `CredentialStore`, Foundation.

### `UsageFormatter.swift`

Fonctions pures, sans état ni dépendance système : transformation d'un
`UsageSnapshot` en texte de barre de menus, choix de la couleur selon
les seuils, et mise en forme des heures de réinitialisation.

Dépend de : Foundation, AppKit (pour `NSColor` uniquement).

### `MenuBarController.swift`

Crée le `NSStatusItem`, construit le menu, gère le minuteur et réagit
aux actions. Prend un `UsageFetching` par injection.

Dépend de : `UsageClient`, `UsageFormatter`, AppKit.

### `main.swift`

Point d'entrée : instancie l'application, l'assemble et la démarre.

## Construction et installation

- Paquet Swift Package Manager, exécutable, sans Xcode.
- Un script `build.sh` compile en mode release puis fabrique un bundle
  `ClaudeUsage.app` contenant l'exécutable et un `Info.plist` avec
  `LSUIElement` à `true`, ce qui supprime l'icône du Dock.
- Le script copie le bundle dans `/Applications` si l'utilisateur le
  demande explicitement ; par défaut il le laisse dans le dossier de
  construction.
- Le lancement automatique au démarrage n'est pas géré par
  l'application : le fichier `README.md` explique comment ajouter le
  bundle aux ouvertures automatiques dans les Réglages Système.

## Tests

Cible de test Swift Testing (ou XCTest), portant uniquement sur la
logique pure et le décodage :

- décodage d'une réponse JSON complète de l'API vers `UsageSnapshot` ;
- décodage d'une réponse tronquée ou malformée : produit l'erreur
  attendue ;
- texte de la barre de menus pour des valeurs entières, décimales et
  nulles ;
- choix de la couleur aux bornes exactes des seuils (69, 70, 89, 90) ;
- mise en forme d'une date de réinitialisation.

Le trousseau et le réseau ne sont pas testés directement : ils sont
remplacés par des doublures conformes à `CredentialProviding` et
`UsageFetching`.

## Conventions

- Noms de types, de fonctions et de variables en anglais.
- Commentaires de code, documentation et fichier `README.md` en
  français.

## Hors périmètre

- Historique ou graphique d'utilisation.
- Notifications à l'approche d'une limite.
- Réglages configurables (seuils, fréquence).
- Gestion des limites par modèle ou des crédits supplémentaires.
