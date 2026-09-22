# Claude Usage

Un petit indicateur dans la barre de menus de macOS qui montre en
permanence deux pourcentages : l'utilisation de la limite glissante de
cinq heures et celle de la limite hebdomadaire du plan Claude.

    10% · 2%

Le premier nombre est la limite 5 heures, le second la limite
hebdomadaire. Le texte passe en orange à partir de 70 % et en rouge à
partir de 90 %.

Un clic ouvre un menu qui détaille les deux limites avec leur heure de
remise à zéro, et propose de rafraîchir ou de quitter.

## Installation

Depuis la page des releases, télécharger `ClaudeUsage-X.Y.Z.zip`, le
décompresser et glisser `ClaudeUsage.app` dans `/Applications`.

L'application n'est pas notarisée par Apple, faute de compte
développeur. Au premier lancement, macOS refuse donc de l'ouvrir. Il
faut faire un clic droit sur l'application, choisir « Ouvrir », puis
confirmer ; ce n'est à faire qu'une fois. Si l'avertissement persiste :

    xattr -dr com.apple.quarantine /Applications/ClaudeUsage.app

Pour construire soi-même depuis les sources :

    ./build.sh --install

L'application arrive dans `/Applications`. Sans argument, le bundle
reste dans `build/` ; avec `--zip`, le script produit en plus l'archive
distribuée dans les releases.

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

Si la barre affiche des points de suspension, ouvrir le menu : il explique ce qui ne va
pas. Dans la plupart des cas, il suffit de relancer Claude Code pour
renouveler la session.

## Développement

    swift build --build-system native              # compiler
    swift run --build-system native ClaudeUsageChecks   # lancer les vérifications
    swift run --build-system native ClaudeUsage    # lancer sans fabriquer de bundle

Le drapeau `--build-system native` est nécessaire tant qu'Xcode n'est
pas installé : sans lui, le moteur de compilation par défaut de Swift
6.4 refuse de démarrer.

Le numéro de version vit uniquement dans
`Sources/ClaudeUsageCore/Version.swift` ; `build.sh` le recopie dans
l'`Info.plist` du bundle, et le workflow de release vérifie que le tag
poussé lui correspond.

Pour la même raison, les tests n'utilisent ni XCTest ni Swift Testing,
absents des seuls outils en ligne de commande. Ils prennent la forme
d'un petit exécutable de vérification, `ClaudeUsageChecks`, qui renvoie
un code d'erreur si un cas échoue.

### Organisation

- `Sources/ClaudeUsageCore` : toute la logique : modèle, décodage de la
  réponse de l'API, lecture du trousseau, client réseau, mise en forme
  de l'affichage et contrôleur de la barre de menus.
- `Sources/ClaudeUsage` : le point d'entrée de l'application.
- `Sources/ClaudeUsageChecks` : les vérifications automatiques.

### Publier une version

Demander à Claude Code de publier la version voulue : la skill
`release` fusionne `develop` dans `main`, met le numéro à jour, pose le
tag et pousse le tout. GitHub Actions construit alors l'archive et
l'attache à la release.

Le code et les noms sont en anglais, les commentaires et la
documentation en français.
