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

Dans une session Studio avec le service intégré par le bootstrap, vérifier en solo puis à quatre : confirmation de tous, recette, lavage, double prise et double service refusés, interruption de travail à distance, refus hors portée, patience expirée, fin du temps avec client restant, déconnexion et nettoyage `stop`. `tests/gameplay/Gameplay.spec.luau` est un scénario à coller dans la Command Bar serveur en Play avec un joueur, dans une copie de test dont le bootstrap serveur est désactivé ; voir `README.md`. Aucun résultat Studio n'est revendiqué ici.
