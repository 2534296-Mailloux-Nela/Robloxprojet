# Bugs et vérifications à reprendre

Statut au 29 octobre 2026 : le prototype a été lancé dans Roblox Studio sur `RestaurantSlice-test.rbxlx` (place de test générée par Rojo), et l'utilisateur a observé le HUD et la phase Service. Ce n'est **pas** une validation du parcours de jeu complet.

## Incident observé : impossible de prendre les ingrédients

- Capture utilisateur : phase Service, personnage près des stations, HUD « Cible : aucune · Main : vide ». Les actions sur les ingrédients ne fonctionnent pas.
- Cause identifiée dans les sources : sur PC, le client ne ciblait une station que lorsque le rayon de la souris touchait directement son bloc. Le passage de la souris sur un bouton du HUD supprimait cette cible ; la proximité seule ne suffisait pas. Depuis le point d'apparition, la station Ingredient est initialement hors de la portée serveur de 12 studs.
- Correctif client **non vérifié dans Studio** : repli vers la station la plus proche à portée, rafraîchissement pendant le déplacement, message d'aide sans cible et traitement de l'appui sur le bouton « Travailler ». Fichiers : `src/client/Controllers/InputController.luau`, `src/client/Controllers/UIController.luau`, `src/client/Bootstrap.client.luau`.

## Réserves découvertes pendant la revue du correctif

Les risques techniques 1–4 ont un correctif dans les sources client, non vérifié dans Studio ; **ne pas annoncer l'incident résolu** avant recette :

1. Corrigé statiquement : `InputController.luau` vérifie que le résultat du raycast est une `BasePart` avant de lire `Position`. Tester le rayon contre `Terrain` en Studio ; le serveur reste arbitre de la portée.
2. Corrigé statiquement : cache des descendants rafraîchi au plus toutes les 0,15 s et sélection limitée à 0,1 s. Profiler en Studio ; le client utilise `< 11,9` studs et le serveur valide `<= 12`.
3. Corrigé statiquement : la cible touchée reste prioritaire tant qu'elle est à portée. Les boutons HUD mémorisent la cible au début de l'appui souris/tactile et l'utilisent à l'activation, sans se rabattre sur la nouvelle station si la cible initiale est absente. Vérifier en Studio avec joystick mobile et déplacement durant l'appui ; le serveur vérifie toujours la portée.
4. Corrigé statiquement : l'entrée qui a initié `BeginWork` possède le maintien (`F`, `R2` ou HUD). Un second appui est ignoré et son relâchement ne termine plus le travail de la première source ; perte de focus et disparition du personnage forcent toujours `EndWork`. Vérifier relâchement hors bouton, annulation tactile, navigation manette et appuis croisés en Studio. Les protections serveur restent nécessaires.
5. Tester réellement la recette salade (prise, planche, découpe, assiette, commande, service, évier), le changement de jour, la déconnexion et deux joueurs. Vérifier Output client/serveur ; aucun test de cette liste n'est confirmé réussi.

## État local et reprise

- Rojo 7.7.1 et son plugin Studio ont été installés ; la place de test `RestaurantSlice-test.rbxlx` a été générée et ouverte. Elle est ignorée par Git, et reflète une **version antérieure** aux correctifs client non testés ; reconstruire la place de test avant la prochaine recette, puis rouvrir dans Studio.
- `projet4000.rbxl` présente une modification locale de l'utilisateur. La préserver : **ne pas l'inclure dans le commit de bugfix, ne pas l'écraser, ne pas synchroniser Rojo dessus**. Le fichier `.lock` de Studio reste ignoré.
- La suite de production (cuisson, placement, automatisation, sauvegarde) reste soumise à validation explicite distincte. La résolution de cet incident est une correction de la tranche actuelle, pas le lancement de ce prochain lot.
