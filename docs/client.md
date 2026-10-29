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
une Part ou un parent; un raycast client PC/mobile/manette identifie la
cible. L'interaction contextuelle lit `InteractionAction` sur cette même
instance et n'émet que `BeginWork`, `TakeOrder` ou `Serve`. Sinon, les
boutons explicites Prendre, Poser, Travailler, Commande et Servir envoient
l'action sur la cible sélectionnée. Les boutons tactiles de
`ContextActionService` proposent aussi les contrôles sur mobile/manette.
Le client ne construit aucun identifiant de station/recette fixe.

Contrôles clavier : souris/raycast pour la cible, `E` interaction, `Q`
prendre, `R` poser, `F` travail, `1` commande, `2` servir, `Y` prêt.
Les binds CAS fournissent les boutons tactiles/manette adaptés. En phase de
préparation, `F` doit être maintenu; le relâchement, l'annulation d'input ou
la disparition du personnage envoient `EndWork`. La durée de travail et sa
validation restent serveur. `SetReady` bascule depuis l'état confirmé.

## Portée et recette manuelle

L'écran couvre phase, jour, temps, argent partagé, commandes/patience,
cible, confirmations/refus et boutons d'action avec attente de connexion.
Achat de plans, cartes, monnaie permanente et placement ne sont pas
implémentés : ils ne sont pas exposés comme boutons fictifs. Les actions
NextDay/EndWork doivent être autorisées/rejetées par le serveur selon phase
et droits. Le résumé/fermeture est affiché par la phase dans le HUD; le
serveur décide des transitions.

## Vérifications proposées (Studio)

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
6. Maintenir/relâcher F et tester perte de focus/disparition personnage;
   confirmer qu'un seul BeginWork et un EndWork sont envoyés, sans boucle.
7. Vérifier navigation focus clavier/manette et lisibilité sur viewport
   étroit et touch. Confirmer les attributs `TargetId`/
   `InteractionAction` des Parts livrées par le serveur.

Aucun test Studio n'a été exécuté dans cet environnement. Snapshot chunké,
révisions d'entités, relance idempotente après perte d'ack et sélection
nearest sans cible sous le réticule nécessitent un contrat serveur plus
précis avant d'être revendiqués.
