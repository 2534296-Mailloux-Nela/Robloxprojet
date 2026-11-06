# Vertical slice gameplay

## Intégration

`Services/GameService.luau` exporte `new()`, puis `start()`, `stop()`, `handleAction(player, action, payload)` et `getSnapshot(player)`. `onStateChanged`, si renseigné, est appelé après les mutations, y compris les ticks ; Sol publie les snapshots et route les actions. Aucun Remote n'est créé par le service. `start` crée `workspace.RestaurantSlice`, un sol, un point d'apparition et les stations ; `stop` déconnecte les événements et détruit ce modèle. Une instance de service par restaurant est nécessaire. Les quatre premiers joueurs connectés participent ; les autres sont refusés. Lorsqu'un joueur arrive ou quitte en préparation, les confirmations sont annulées.

Le snapshot contient `runId`, `phase`, `day`, `money`, `timeRemaining`, `readyPlayers`, `players`, `stations`, `customers`, `message` selon l'API demandée. Les cartes joueurs utilisent `tostring(UserId)` ; `heldItem` absent signifie mains vides. `progress` est compris entre 0 et 1. `timeRemaining` et `patience` sont en secondes serveur. Un snapshot est une copie, pas une référence à l'état interne.

## Ciblage et actions

Toutes les stations sont des Parts portant `TargetId`, `InteractionAction`, `PickUpAction` et `WorkAction`. `InteractionAction` est une action par défaut, pas une garantie de validité dans tous les états ; l'interface doit proposer aussi prendre, poser, travailler, commander et servir. Les actions ciblées utilisent `{targetId = id}` ; `Serve` cible **table**, pas l'identifiant client. `EndWork` utilise `{}` ; `SetReady` utilise `{ready = boolean}` ; `NextDay` utilise `{}`. Les refus retournent `(false, code)` et ne modifient pas l'état. La distance maximale est de 12 studs depuis `HumanoidRootPart`, vérifiée côté serveur. Le travail est interrompu si le joueur s'éloigne, se déconnecte ou si la phase change ; il ne requiert aucun événement par frame. `EndWork` interrompt avant achèvement.

| TargetId | Kind | Actions valides et état |
| --- | --- | --- |
| `ingredient` | `Ingredient` | `PickUp` : laitue illimitée si mains vides |
| `board` | `Board` | `PutDown` laitue ; `BeginWork` découpe ; `PutDown` assiette propre sur laitue découpée crée salade ; `PickUp` récupère contenu |
| `plates` | `PlateRack` | `PickUp` assiette propre ; `PutDown` assiette propre |
| `counter` | `Counter` | `PutDown` et `PickUp` pour stocker un objet |
| `sink` | `Sink` | `PutDown` assiette sale ; `BeginWork` lavage ; `PickUp` assiette propre |
| `table` | `Table` | `TakeOrder`, `Serve` avec salade en main, `PickUp` assiette sale |

## Parcours

1. Tous les participants envoient `SetReady` à vrai. Le service commence automatiquement.
2. À la table, `TakeOrder`. Prendre une laitue à `ingredient`, la poser sur `board`, commencer `BeginWork` et rester à portée pendant 3 secondes.
3. Prendre l'assiette propre à `plates`, la poser sur `board` pour dresser la salade, puis prendre la salade. `Serve` sur `table` crédite 10 une seule fois.
4. Prendre l'assiette sale à la table, la poser dans `sink`, travailler 3 secondes, puis récupérer l'assiette propre pour recommencer. Une nouvelle arrivée attend que la table soit débarrassée.
5. À la fin du chronomètre, aucune arrivée supplémentaire ; un client présent doit encore être servi. Si sa patience expire, phase `Closed` ; sinon phase `Summary` et `NextDay` lance la préparation suivante.

## Adaptations et limites

Carte fixe, 1 table, 1 client à la fois, 3 arrivées au maximum, service 100 s, patience 90 s, intervalle 15 s, travail 3 s et prix 10 : valeurs de prototype, non validées comme constantes wiki. Les clients sont représentés par leur état dans le snapshot, sans PNJ ni déplacement ; le repas est instantané. Le jour suivant réinitialise inventaire et vaisselle : pas de persistance, achats, cartes, cuisson, déchets, layout modifiable, navigation ou automatisation. L'échec clôt la run sans redémarrage ; redémarrer une instance crée une nouvelle run. Le serveur vérifie la portée mais ne détecte pas les déplacements impossibles ; Sol doit assurer validation réseau, limitation de débit et déduplication. Aucun checkpoint ni bail de persistance n'est implémenté ici. Les éléments visuels sont des Parts et ne prouvent pas l'accessibilité ni les performances sur appareil réel.

## Validation manuelle

Dans une session Studio avec le service intégré par le bootstrap, vérifier en solo puis à plusieurs : confirmation de tous, recette, lavage, double prise et double service refusés, interruption de travail à distance, refus hors portée, patience expirée, fin du temps avec client restant, déconnexion et nettoyage `stop`. `tests/gameplay/Gameplay.spec.luau` est un scénario à coller dans la Command Bar serveur en Play avec un joueur, dans une copie de test dont le bootstrap serveur est désactivé ; voir `README.md`. Il vérifie notamment la limite serveur à 12 studs, le refus à 12,1 studs et l'annulation du travail hors portée. Aucun résultat Studio n'est revendiqué ici.

### Recette de ciblage client à exécuter

Depuis la racine du dépôt, reconstruire `RestaurantSlice-test.rbxlx` avec `C:/Users/2531075/Tools/rojo.exe build default.project.json -o RestaurantSlice-test.rbxlx` (ou utiliser le plugin Rojo dans une nouvelle place de test). Ouvrir ou rouvrir **la place de test reconstruite**, jamais `projet4000.rbxl` ; garder les deux bootstraps actifs, ouvrir Output client et serveur, puis lancer Play. Les scénarios ci-dessous sont manuels : la Command Bar ne fournit pas de simulation fiable des entrées souris, tactile et manette utilisées par le contrôleur.

1. En Service, partir loin de toute station : vérifier « Cible : aucune » et l'aide affichée. Approcher `ingredient` sans viser son bloc ; vérifier que la cible devient accessible, puis cliquer « Prendre » dans le HUD : la main doit contenir `Lettuce`. Déplacer le curseur sur le HUD avant de cliquer et vérifier que l'action concerne toujours la station attendue.
2. Viser directement une station accessible, puis déplacer le personnage sans bouger la souris : vérifier que la cible s'actualise en entrant et sortant de portée. Avec le harnais serveur (pas le ciblage client, limité à < 11,9 studs), vérifier 12 studs acceptés et 12,1 refusés. Vérifier aussi un rayon passant sur du terrain Roblox `Terrain`, sans erreur dans Output.
3. Sur appareil tactile, toucher directement une station accessible puis utiliser le HUD : vérifier que la sélection explicite reste la même pendant le déplacement du doigt et le rafraîchissement, tant que la station reste accessible ; s'éloigner et vérifier qu'elle cesse d'être utilisable. Répéter avec deux stations proches pour détecter un changement de cible inattendu.
4. Poser une laitue sur `board`, maintenir « Travailler », puis relâcher hors du bouton avant 3 secondes : la progression doit s'arrêter et revenir à zéro. Répéter avec annulation tactile et autre doigt posé sur l'écran, touche `F`, `R2` et bouton HUD sélectionné puis maintenu avec `A` à la manette ; vérifier qu'aucun travail ne reste actif après relâchement ou annulation. Maintenir ensuite 3 secondes pour confirmer la découpe, puis tester l'interruption en s'éloignant.
5. Terminer la recette : prendre commande, dresser et servir la salade, vérifier +10 une seule fois, récupérer l'assiette sale, la laver et la ranger. Enchaîner jusqu'au bilan et au jour suivant. Répéter à deux joueurs : les deux doivent être prêts, puis vérifier l'état partagé et la déconnexion pendant un travail ou avec une assiette en main.
6. Sur une session prolongée et avec plusieurs stations, observer le MicroProfiler Studio pendant les déplacements et changements de cible : rechercher un coût récurrent anormal du ciblage ou des scans de descendants. Noter appareil, durée, résultats et erreurs client/serveur ; ne pas déduire les performances d'un appareil réel de la seule émulation Studio.
