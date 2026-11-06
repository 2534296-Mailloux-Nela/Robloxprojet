# Bugs et vérifications à reprendre

Statut au 6 novembre 2026 : l'utilisateur avait observé le HUD et la phase Service dans Studio sur `RestaurantSlice-test.rbxlx` (place de test Rojo) le 29 octobre. Cela ne valide ni le parcours complet ni les correctifs intervenus depuis. **Ancien bug de ciblage corrigé statiquement dans les sources, résolution en runtime non confirmée.**

## Incident observé : impossible de prendre les ingrédients

- Capture utilisateur : phase Service, personnage près des stations, HUD « Cible : aucune · Main : vide ». Les actions sur les ingrédients ne fonctionnent pas.
- Cause identifiée dans les sources : sur PC, le client ne ciblait une station que lorsque le rayon de la souris touchait directement son bloc. Le passage de la souris sur un bouton du HUD supprimait cette cible ; la proximité seule ne suffisait pas. Depuis le point d'apparition, la station Ingredient est initialement hors de la portée serveur de 12 studs.
- Correctif présent et vérifié **par lecture statique seulement**, non vérifié dans Studio : repli vers la station la plus proche à portée, rafraîchissement pendant le déplacement, message d'aide sans cible et traitement de l'appui sur le bouton « Travailler ». Fichiers : `src/client/Controllers/InputController.luau`, `src/client/Controllers/UIController.luau`, `src/client/Bootstrap.client.luau`. Ne pas qualifier l'incident de résolu en jeu avant recette.

## Réserves découvertes pendant la revue du correctif

Les risques techniques 1–4 sont corrigés **statiquement** dans les sources client, mais non validés dans Studio. Le runtime souris, tactile, manette et deux joueurs reste **non validé** ; ne pas annoncer l'incident résolu en jeu avant recette :

1. Corrigé statiquement : `InputController.luau` vérifie que le résultat du raycast est une `BasePart` avant de lire `Position`. Tester le rayon contre `Terrain` en Studio ; le serveur reste arbitre de la portée.
2. Corrigé statiquement : cache des descendants rafraîchi au plus toutes les 0,15 s et sélection limitée à 0,1 s. Profiler en Studio ; le client utilise `< 11,9` studs et le serveur valide `<= 12`.
3. Corrigé statiquement : la cible touchée reste prioritaire tant qu'elle est à portée. Les boutons HUD mémorisent la cible au début de l'appui souris/tactile et l'utilisent à l'activation, sans se rabattre sur la nouvelle station si la cible initiale est absente. Vérifier en Studio avec joystick mobile et déplacement durant l'appui ; le serveur vérifie toujours la portée.
4. Corrigé statiquement : l'entrée qui a initié `BeginWork` possède le maintien (`F`, `R2` ou HUD). Un second appui est ignoré et son relâchement ne termine plus le travail de la première source ; perte de focus et disparition du personnage forcent toujours `EndWork`. Vérifier relâchement hors bouton, annulation tactile, navigation manette et appuis croisés en Studio. Les protections serveur restent nécessaires.
5. Tester réellement la recette salade (prise, planche, découpe, assiette, commande, service, évier), le changement de jour, la déconnexion et deux joueurs. Vérifier Output client/serveur ; aucun test de cette liste n'est confirmé réussi.

## Validation effectuée hors Studio (6 novembre 2026)

Depuis la racine du dépôt, commande exécutée :

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/test-runner/Validate-Place.ps1 -RojoPath 'C:/Users/2531075/Tools/rojo.exe'
```

Sortie observée :

```text
PASS: Rojo build + sourcemap + XML: 21 instances, 5 RemoteEvents, 7 exact embedded scripts
PASS: Static protocol v1: 8 actions, 5 remotes referenced by both endpoints
```

Ce contrôle **structurel** construit une place dans `build/` (ignorée par Git) et vérifie le mapping, les sources intégrées et quelques références statiques au protocole ; il ne compile ni n'exécute les tests Luau, ne démarre pas Play et ne simule pas les entrées. **Aucun des cinq scénarios Command Bar n'a été exécuté ici** (`Protocol`, `NetworkSmoke`, `UIController`, `Gameplay`, `Coop`) ; aucun `... passed` Studio n'est revendiqué.

## Reprise manuelle pour l'utilisateur (non effectuée)

1. Depuis la racine, reconstruire **une place de test séparée** avec `C:/Users/2531075/Tools/rojo.exe build default.project.json -o RestaurantSlice-test.rbxlx` (adapter le chemin Rojo), puis **rouvrir ce fichier dans Studio**. Ne jamais sortir vers `projet4000.rbxl` et ne pas y synchroniser Rojo. `RestaurantSlice-test.rbxlx` précédemment ouvert était antérieur aux correctifs.
2. Garder les deux bootstraps actifs pour Play. En solo, approcher `ingredient` sans viser la Part, passer le curseur sur le HUD, cliquer « Prendre » et confirmer `Lettuce` ; refaire la recette salade, travail maintenu, service et lavage. Vérifier la portée et les erreurs dans Output **client et serveur**. Sur écran tactile réel, toucher une station et maintenir/relâcher « Travailler » ; à la manette réelle, vérifier visée/focus et maintien `R2`. Tester aussi l'annulation, deux sources d'appui et le changement de cible pendant un appui.
3. Dans Studio > Test > 2 Players, vérifier les deux votes « Prêt », l'état partagé, la déconnexion/reconnexion et la fin de journée. Consigner appareil, étapes, résultat et erreurs Output : les modes souris/touch/manette et deux joueurs restent non validés tant que ces essais n'ont pas réussi.
4. Si souhaité, exécuter **manuellement** les cinq scripts Command Bar, séparément dans des copies jetables, avec le bon bootstrap désactivé avant Play et le bon contexte Server/Client. `README.md` donne les étapes rapides, les lignes de succès **à attendre**, `docs/gameplay.md` et `docs/client.md` détaillent les limites. Le runner PowerShell ne lance aucun de ces scripts.

La suite de production (cuisson, placement, automatisation, sauvegarde) reste soumise à validation explicite distincte. La correction statique de cet incident n'autorise pas le lancement de ce prochain lot.
