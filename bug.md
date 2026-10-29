# Bugs et vérifications à reprendre

Statut au 29 octobre 2026 : le prototype a été lancé dans Roblox Studio sur `RestaurantSlice-test.rbxlx` (place de test générée par Rojo), et l'utilisateur a observé le HUD et la phase Service. Ce n'est **pas** une validation du parcours de jeu complet.

## Incident observé : impossible de prendre les ingrédients

- Capture utilisateur : phase Service, personnage près des stations, HUD « Cible : aucune · Main : vide ». Les actions sur les ingrédients ne fonctionnent pas.
- Cause identifiée dans les sources : sur PC, le client ne ciblait une station que lorsque le rayon de la souris touchait directement son bloc. Le passage de la souris sur un bouton du HUD supprimait cette cible ; la proximité seule ne suffisait pas. Depuis le point d'apparition, la station Ingredient est initialement hors de la portée serveur de 12 studs.
- Correctif client **non vérifié dans Studio** : repli vers la station la plus proche à portée, rafraîchissement pendant le déplacement, message d'aide sans cible et traitement de l'appui sur le bouton « Travailler ». Fichiers : `src/client/Controllers/InputController.luau`, `src/client/Controllers/UIController.luau`, `src/client/Bootstrap.client.luau`.

## Réserves découvertes pendant la revue du correctif

Ces points demandent un correctif sous-agent et une recette Studio ; **ne pas annoncer l'incident résolu** avant vérification :

1. `InputController.luau` lit `result.Instance.Position` après un raycast sans vérifier que l'instance est une `BasePart` : si le rayon touche `Terrain`, risque d'erreur runtime. Garder la validation de portée côté serveur et vérifier le type de l'instance avant lecture.
2. Le nouveau repli recherche des descendants à chaque `Heartbeat`, sans mise en cache ni limite de fréquence. Profiler et réduire le coût ; vérifier la borne (`< 12` côté client contre `<= 12` côté serveur).
3. Le rafraîchissement automatique peut écraser une station choisie au toucher, ou changer la cible sous le HUD au moment du clic. Préserver la cible explicitement choisie tant qu'elle reste atteignable.
4. Le bouton « Travailler » envoie `EndWork` sur `InputEnded` du bouton lui-même : vérifier relâchement hors bouton, annulation tactile et navigation manette ; ne pas laisser un travail actif sans fin client. Les protections serveur restent nécessaires.
5. Tester réellement la recette salade (prise, planche, découpe, assiette, commande, service, évier), le changement de jour, la déconnexion et deux joueurs. Vérifier Output client/serveur ; aucun test de cette liste n'est confirmé réussi.

## État local et reprise

- Rojo 7.7.1 et son plugin Studio ont été installés ; la place de test `RestaurantSlice-test.rbxlx` a été générée et ouverte. Elle est ignorée par Git, et reflète une **version antérieure** aux correctifs client non testés ; reconstruire la place de test avant la prochaine recette, puis rouvrir dans Studio.
- `projet4000.rbxl` présente une modification locale de l'utilisateur. La préserver : **ne pas l'inclure dans le commit de bugfix, ne pas l'écraser, ne pas synchroniser Rojo dessus**. Le fichier `.lock` de Studio reste ignoré.
- La suite de production (cuisson, placement, automatisation, sauvegarde) reste soumise à validation explicite distincte. La résolution de cet incident est une correction de la tranche actuelle, pas le lancement de ce prochain lot.
