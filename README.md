# Galerie — galerie photo & vidéo iOS (SwiftUI, PhotoKit)

Alternative personnalisable à Photos : navigation à 5 onglets (Collections · Recherche · **Photothèque** · Carte · Réglages), Liquid Glass (iOS 26) avec repli translucide, thèmes complets, polices importables, carte de toute la photothèque, éditeurs photo et vidéo, haptique, icônes alternatives.

## Tutoriel : obtenir l'app sur ton iPhone depuis GitHub (tout depuis le téléphone)

1. **Récupère `Galerie-source.zip`** (téléchargé depuis Claude, enregistré dans Fichiers). Ne le décompresse pas.
2. Ouvre ton dépôt dans **Safari** (github.com/ziakajen91400-beep/Galerie), menu `aA` › *Demander le site pour ordinateur*.
3. Crée le workflow de déballage : **Add file › Create new file**, nom : `.github/workflows/unpack.yml` (tape le `/` pour créer les dossiers), colle le contenu du fichier `unpack.yml` fourni, puis **Commit changes**.
4. **Add file › Upload files**, choisis `Galerie-source.zip` (le nom doit rester exactement `Galerie-source.zip`), **Commit changes**.
5. Onglet **Actions** : « Déballer l'archive » s'exécute (≈ 30 s), commit tous les fichiers, puis lance **Build iOS** (matrice macOS 15 + macOS 26 expérimental).
6. Quand « Build iOS » est vert, ouvre l'exécution › section **Artifacts** › télécharge `Galerie-unsigned-ipa-macos-15` (ZIP contenant `Galerie-unsigned.ipa`).
   - Si ça échoue : télécharge l'artefact `logs-macos-15` (`build.log`, `test.log`) et envoie-le moi, je corrige.
   - Si ton ancien dépôt avait un autre workflow de build, supprime-le pour éviter les doublons.
7. **Installer** : l'IPA est **NON SIGNÉ**, iOS refuse de l'installer tel quel. Il faut le signer avec ton identifiant Apple :
   - **Gratuit (certificat valable 7 jours)** : Sideloadly (Mac/PC) ou AltStore/SideStore, qui re-signent l'IPA.
   - **Compte développeur payant (99 €/an)** : signature ad hoc / TestFlight, valable 1 an.
   - Avec un compte gratuit, « Se connecter avec Apple » n'est pas disponible (voir plus bas) ; tout le reste fonctionne, y compris les icônes alternatives.
8. Au premier lancement, autorise l'accès aux photos (idéalement « Accès complet »).

## Connexion avec Apple (optionnel, compte payant)
Dans `project.yml` : décommente `SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) APPLE_SIGN_IN"` et le bloc `entitlements`, puis active la capacité *Sign in with Apple* sur ton App ID. Cette connexion ne donne **pas** accès à ta photothèque iCloud : elle fournit seulement nom/e-mail (si tu les partages).

## Structure
```
project.yml                 XcodeGen (iOS 18.5, Swift 5 mode, icônes alternatives)
Galerie/Core                Thèmes, polices, réglages, haptique, icônes
Galerie/Library             PhotoKit : bibliothèque, vignettes, actions, albums
Galerie/UI                  Navigation 5 onglets, grille, visionneuse, collections, recherche, réglages
Galerie/Features            Infos/EXIF, carte, souvenirs, analyse Vision locale, profil, apparence
Galerie/Editor              Éditeur photo (Core Image) et vidéo (AVFoundation)
Galerie/Assets.xcassets     12 icônes d'app + aperçus (générées par Tools/make_icons.py)
GalerieTests                Tests unitaires
.github/workflows           build.yml (CI) · unpack.yml (import depuis iPhone)
```

## Tests manuels nécessitant un vrai iPhone
Autorisation complète/limitée · grille avec vos vraies photos · pincement · ouverture photo/vidéo/Live Photo · favoris/partage/suppression · carte avec photos géolocalisées (regroupement, panneau, ouverture d'une photo, Plans/Google Maps) · haptique (activer/désactiver, redémarrer l'app) · changement d'icône sur l'écran d'accueil · import d'une police TTF/OTF · éditeur photo (enregistrer/copie) · export vidéo · thèmes clair/sombre.

## Limites iOS (résumé — détail dans Réglages › Aide et limites)
Pas d'accès à « Supprimés récemment », personnes/animaux, album partagé en famille, date d'ajout, état iCloud · légendes/mots-clés stockés dans l'app uniquement · réglages d'édition = approximations Core Image (pas les algorithmes d'Apple) · mixages audio Apple non reproduits · gain map HDR et partie animée des Live Photos perdues à l'édition.
