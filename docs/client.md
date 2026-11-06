# Client vertical slice

## Intégration

`src/client/Bootstrap.client.luau` doit être installé comme `LocalScript` dans
`StarterPlayer/StarterPlayerScripts`. Ses contrôleurs sont des modules voisins.
Le serveur doit publier ces `RemoteEvent` sous `ReplicatedStorage/Remotes` :
`ActionRequest`, `ActionResult`, `StateDelta`, `SnapshotRequest` et
`StateSnapshot`. Aucun `RemoteFunction` n'est utilisé.

Le client envoie `protocolVersion = 1`, un GUID de session combiné à un
séquenceur dans `requestId`, `runId`, `action`,
`expectedEntityRevisions = {}` et `payload`. Actions émises : `SetReady`
avec `{ready}`, `PickUp`, `PutDown`, `BeginWork`, `TakeOrder`, `Serve`
avec `{targetId}`, `EndWork` et `NextDay`. Les révisions d'entités ne sont
pas encore exposées par le snapshot décrit; elles restent donc vides. Le
serveur reste responsable de valider toutes les actions et de l'argent, du
temps, des objets et des résultats.

Un snapshot complet initial est attendu avec `chunkIndex = 1` et
`chunkCount = 1`. Les snapshots multi-chunks sont refusés explicitement,
car le contrat de slice ne définit pas ici une identité/expiration assez
complète pour assembler sûrement les fragments. Tout delta non contigu,
d'un autre run ou sans `changes.snapshot` demande un snapshot; les deltas
ne sont jamais appliqués de façon optimiste. `ActionResult` corrèle
uniquement les requêtes en attente et affiche Accepté/Refusé avec code et
révision confirmée. Aucun rejeu automatique d'action n'est fait.

## Ciblage et contrôles

Les pièces interactives du monde doivent exposer `TargetId` (string) sur
une Part ou un parent dans `workspace.RestaurantSlice`. Une sélection
explicitement touchée reste prioritaire tant que la station est à portée ;
sinon, un raycast valide est prioritaire, puis la station BasePart la plus
proche à moins de 11,9 studs, avec départage par identifiant. Le cache de
candidats est rafraîchi au plus toutes les 0,15 s, et immédiatement lors
d'un toucher explicite. Le pointeur au-dessus du HUD conserve la cible
précédente seulement si elle est encore à portée. Le serveur reste seul
arbitre de la portée (inférieure ou égale à 12 studs, avec marge client).
L'interaction contextuelle n'émet que les actions définies par le flux
client ; aucun attribut client ne fait autorité. Les boutons explicites
Prendre, Poser, Travailler, Commande et Servir envoient
l'action sur la cible sélectionnée. Un appui souris/tactile sur un bouton
HUD capture cette cible dès `InputBegan` et la réutilise à `Activated`, même
si le joystick ou la sélection automatique la modifie entre-temps ; sans
cible au début de l'appui, l'action ne se recible pas à la fin. Le serveur
reste responsable de la validation de portée au moment de la requête. Les
boutons tactiles de `ContextActionService` proposent aussi les contrôles sur mobile/manette.
Le client ne construit aucun identifiant de station/recette fixe.

Contrôles clavier : souris/raycast pour la cible, `E` interaction, `Q`
prendre, `R` poser, `F` travail, `1` commande, `2` servir, `Y` prêt.
Les binds CAS fournissent aussi les contrôles tactiles/manette adaptés.
Pour découper ou laver en phase Service, maintenir `F`, `R2` ou le bouton
« Travailler » (souris/toucher, `A` sur le bouton sélectionné à la manette).
Le relâchement, l'annulation d'input, la perte de focus et la disparition du
personnage interrompent le travail. Un seul maintien est propriétaire du
travail : un second appui (`F`, `R2` ou HUD) est ignoré et son relâchement
n'envoie pas `EndWork` ; seule la source propriétaire peut l'interrompre,
sauf perte de focus ou disparition du personnage. La durée et la
validation restent serveur. `SetReady` bascule
depuis l'état confirmé.

## Portée et recette manuelle

L'écran couvre phase, jour, temps, argent partagé, commandes/patience,
cible, confirmations/refus et boutons d'action avec attente de connexion.
Achat de plans, cartes, monnaie permanente et placement ne sont pas
implémentés : ils ne sont pas exposés comme boutons fictifs. Les actions
NextDay/EndWork doivent être autorisées/rejetées par le serveur selon phase
et droits. Le résumé/fermeture est affiché par la phase dans le HUD; le
serveur décide des transitions.

## Vérifications

`tests/client/UIController.spec.luau` est un smoke test à coller dans la
Command Bar **client** pendant Play. Avant de lancer Play, désactiver le
`LocalScript` de bootstrap client dans le template
`StarterPlayer/StarterPlayerScripts` : le test crée lui-même une UI et ne doit
pas entrer en concurrence avec le bootstrap. Le script vérifie d'abord la
présence du client (`Players.LocalPlayer`), puis attend au plus 10 secondes
chaque élément de `LocalPlayer.PlayerScripts.Controllers.UIController` et
charge ce module cloné côté client, jamais le template StarterPlayer. Son UI
est détruite même si une assertion échoue. Il couvre l'état sans snapshot,
l'affichage cible/progression/main, l'activation en Service, puis le
verrouillage des actions au Bilan et au retour à l'attente. Il nécessite Studio
et Roblox (UI, `PlayerGui`, services), et ne s'exécute pas hors Studio.
Les callbacks d'activation ne sont pas simulés : leur test crédible nécessite
des entrées GUI réelles dans Studio, pas l'invocation artificielle d'un signal.

1. Démarrer sans Remotes/snapshot puis vérifier le statut d'attente, sans
   action réseau tant qu'aucun état/run n'est reçu.
2. Envoyer un snapshot valide; vérifier phase/jour/temps/argent, commande,
   cible et boutons tactiles.
3. Tester Accepted puis Rejected (code), puis une réponse inconnue; seule
   l'action en attente doit actualiser le feedback.
4. Appliquer un delta contigu, puis simuler un trou, run différente et
   snapshot fragmenté; vérifier demande de snapshot / refus fragmenté.
5. Cliquer chaque action avec et sans cible; vérifier qu'aucune action
   n'apparaît confirmée avant le résultat serveur.
6. Maintenir/relâcher F et les boutons HUD (relâcher hors bouton, autres
   doigts, souris et `A` manette), tester annulation, perte de focus et
   disparition du personnage ; confirmer un seul BeginWork/EndWork par
   maintien, sans boucle. Maintenir `F`, appuyer puis relâcher « Travailler »
   sur le HUD sans relâcher `F` : le travail doit continuer jusqu'au
   relâchement de `F` (et inversement). Refaire avec `F` et `R2`.
7. Sur mobile, commencer un appui sur « Prendre » avec une station ciblée,
   déplacer le joystick vers une autre station avant de relâcher : la
   requête doit viser la cible du début d'appui, ou être refusée par le
   serveur si elle est devenue hors de portée. Refaire sans cible initiale.
8. Vérifier navigation focus clavier/manette et lisibilité sur viewport
   étroit et touch. Confirmer les attributs `TargetId`/
   `InteractionAction` des Parts livrées par le serveur. Tester aussi le
   rayon contre `Terrain` et la perte de cible à la sortie de portée.

Aucun test Studio n'a été exécuté dans cet environnement. Snapshot chunké,
révisions d'entités et relance idempotente après perte d'ack ne sont pas
pris en charge par ce client.
