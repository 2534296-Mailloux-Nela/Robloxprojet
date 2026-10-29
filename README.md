# RestaurantSlice — vertical slice Roblox

Prototype coopératif **en sources Rojo séparées**. `projet4000.rbxl` est la place existante : ce projet ne la convertit pas et ne modifie ni ce fichier ni `projet4000.rbxl.lock`.

## Import non destructif

1. Installer Rojo et son plugin Roblox Studio sur votre poste. Depuis ce dossier, vérifier `rojo --version` ; aucun outil Roblox n'est inclus dans le dépôt.
2. Dans Studio, créer une **nouvelle place vide**, distincte de `projet4000.rbxl`. Depuis la racine du dépôt, lancer `rojo serve default.project.json` (serveur temporaire, arrêter après synchronisation), puis connecter le plugin Rojo à cette nouvelle place. Ne pas synchroniser sur la place binaire existante.
3. Contrôler dans l'Explorer : `ReplicatedStorage.Shared.Protocol`, `ReplicatedStorage.Remotes.{ActionRequest,ActionResult,StateDelta,SnapshotRequest,StateSnapshot}` (cinq `RemoteEvent`), `ServerScriptService.Services.GameService`, `ServerScriptService.Infrastructure.NetworkService`, `ServerScriptService.Bootstrap` (Script) et `StarterPlayer.StarterPlayerScripts.Bootstrap` (LocalScript), `Controllers.InputController` et `Controllers.UIController` (ModuleScript). **Vérifier la classe de chaque script** avant Play ; si l'arbre diffère, ne pas enregistrer sur la place d'origine.
4. Facultatif : produire une place XML de test séparée par `rojo build default.project.json -o RestaurantSlice-test.rbxlx`. Ne jamais choisir `projet4000.rbxl` comme sortie.

## Recette Play exacte (un joueur)

1. Lancer Play sur la **nouvelle place**, attendre le snapshot : HUD « Préparation », jour 1 ; six stations et la caisse à 0. Si l'UI reste « Connexion », vérifier Output serveur/client, les cinq Remotes et la présence de `Bootstrap` dans chaque conteneur. Le client redemande un snapshot toutes les 2,5 s jusqu'à réception.
2. Cliquer « Prêt » (ou `G` / `Y` sur manette) : phase « Service », un client à la table. Approcher la table, cibler `table`, puis « Commande » (`1` / `L1`). Vérifier l'ordre salade.
3. Cibler `ingredient`, « Prendre » (`Q` / `X`) : main = `Lettuce`. Cibler `board`, « Poser » (`R` / `B`). Mains vides, cibler `board`, **maintenir** « Travailler » (`F` / `R2`) environ 3 s : progression puis `ChoppedLettuce`. Sur écran tactile, toucher « Travailler » une fois démarre les 3 s côté serveur (s'éloigner annule le travail).
4. Approcher `plates`, « Prendre » : main = `CleanPlate`. À `board`, « Poser » : état `Salad`. « Prendre » sur `board`, puis à `table` « Servir » (`2` / `R1`) : caisse +10 et assiette sale sur table. « Prendre » sur `table`, « Poser » dans `sink`, « Travailler » environ 3 s, puis « Prendre » au `sink`. Déposer l'assiette propre dans `plates` **si libre** pour la prochaine salade, sinon utiliser `counter`.
5. Servir les clients suivants avant épuisement de patience. Le compte à rebours à zéro n'arrête pas une commande en cours ; après tous les clients et la fin du temps, phase « Bilan ». Cliquer « Jour suivant » : jour 2, phase « Préparation », votes prêts remis à faux. Une patience épuisée mène à « Fermé », sans « Jour suivant ».
6. Pour tester la portée, cibler une station lointaine ou envoyer une intention depuis le client : le serveur renvoie `OutOfRange`. Pour deux joueurs, lancer Studio > Test > 2 Players : le premier « Prêt » seul ne lance pas le service ; le second confirme. Vérifier la synchronisation des mains et de la caisse, puis la déconnexion/reconnexion ; maximum quatre participants.

**Saisie** : souris/`E` ou `R3` pour interaction contextuelle, `Q`/`X` prise, `R`/`B` pose, `F`/`R2` travail maintenu, `1`/`L1` commande, `2`/`R1` service, `G`/`Y` prêt. Le GUI contient aussi toutes les actions, y compris « Jour suivant », et ses boutons utilisent des colonnes proportionnelles pour les petits écrans. Taper une station dans le monde tactile sélectionne sa cible ; la manette utilise visée au centre/voisine accessible et navigation de focus GUI. `E`/`R3` adapte l'interaction à la main et à la station ; pour le travail, utiliser « Travailler » plutôt qu'un appui court sur « Interagir ».

## Smoke tests isolés

- `tests/infrastructure/Protocol.spec.luau` : coller le fichier entier dans la **Command Bar serveur** en Play, avec Rojo synchronisé ; attendre `Infrastructure protocol tests passed` dans Output.
- `tests/infrastructure/NetworkSmoke.client.luau` : dans une **copie de test** de la place, désactiver uniquement `Bootstrap.client` (pour libérer le `sessionId` de ce joueur), lancer Play et coller le fichier entier dans la **Command Bar client**. Le bootstrap serveur reste actif. Attendre `Network smoke passed` ; teste snapshot, résultat refusé, déduplication et ID réutilisé avec une autre action. Réactiver `Bootstrap.client` ensuite.
- `tests/gameplay/Gameplay.spec.luau` : dans une autre **copie de test**, désactiver uniquement `Bootstrap.server` pour éviter deux modèles/autorités. Lancer Play avec un joueur, coller le fichier dans la **Command Bar serveur** et attendre `Gameplay smoke passed` ; teste recette, travail, caisse, lavage, transition au jour 2 et nettoyage. Réactiver le bootstrap ensuite. Ce harnais utilise un raccourci de temps pour atteindre le bilan ; le Play normal conserve le chronomètre réel.

Ces scripts ne sont **pas** dans le mapping Rojo et ne sont pas lancés automatiquement. Inspecter Output des deux côtés et répéter la recette sur écran tactile et manette réels ; ni l'émulateur ni la lecture statique ne prouvent ces modes. Voir `docs/infrastructure/README.md` pour le protocole, ses limites et les budgets.

**Hors slice** : DataStore et profils, bail et reprise, franchises, convoyeurs/automatisation, cartes, cuisson et contenu du jeu complet. L'argent et la run disparaissent à la fermeture du serveur. Ne pas publier ce prototype comme jeu durable ou reproduction complète de PlateUp!.
