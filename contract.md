# Contrat de collaboration — Luna, Terra et Sol

Version 0.1 — 29 octobre 2026. Référence fonctionnelle : `agent.md`. Ce contrat organise la conception puis la production ; il ne constitue pas une déclaration d’implémentation ou de tests réussis.

## 1. Gouvernance et ordre de passage

L’orchestrateur valide les règles, arbitre les divergences et autorise les fusions. Mandats transmis séquentiellement : **Luna → Terra → Sol**. Chaque agent remet un compte rendu comprenant décisions, fichiers concernés, contrat consommé/exposé, tests, limites et questions bloquantes.

1. Luna définit parcours, composants et besoins de données sans inventer de règle serveur.
2. Terra transforme ces besoins en états, actions et invariants ; vérifie les règles avec le wiki.
3. Sol sécurise transport, persistance et budgets ; fait corriger les contrats incompatibles.
4. L’orchestrateur fige une version de `Shared/Types` et `Shared/Protocol` avant intégration.
5. Production par lots : infrastructure minimale Sol → gameplay Terra → intégration Luna → recette commune. Cet ordre de dépendances techniques ne change pas l’ordre des mandats de conception.

Les agents ne modifient jamais simultanément la place `.rbxl`. Choisir un workflow source versionné avant tout code. Aucun commit ni changement de branche sans autorisation de l’utilisateur.

### Modèles disponibles et traçabilité

- Luna : `openai-subscribed/gpt-6-luna`.
- Terra : `openai-subscribed/gpt-6.1-terra` (aucun modèle nommé GPT-6-Terra dans la liste disponible).
- Sol : `openai-subscribed/gpt-6-sol`.

Les premiers cadrages Luna/Terra ont été produits sous leurs rôles avec le modèle par défaut ; la consultation infrastructure suivante a explicitement utilisé GPT-6-Sol. Les relectures spécialisées peuvent compléter ces cadrages, sans les présenter comme du code livré.

## 2. Mandats et propriété des fichiers

### Luna — expérience joueur / client

**Écriture future autorisée** : `StarterPlayer/StarterPlayerScripts/Controllers/`, `StarterGui/`, tests UI et documentation UX. Pas de modification des services serveur.

**Mission** : menus de recette et lobby, HUD temps/argent/commandes, jauges et surbrillances, sélection des cartes, bilan, interface Blueprint/Achat, placement sur grille et commandes PC/mobile/console.

**Livrables** : parcours annotés, wireframes et prototype fonctionnel ; contrôleurs UI/input/placement/feedback ; matrice des commandes ; états attente/refus/reconnexion ; liste exacte des données nécessaires. Les mocks restent identifiés comme tels.

**Acceptation** : boucle entière navigable sans souris sur console et sans clavier sur mobile ; previews révocables, aucun achat affiché comme définitif avant confirmation ; focus visible ; pas d’information critique uniquement sonore ou colorée ; lisibilité sur petits écrans et zones sûres. Tester placement accepté/refusé/concurrent/retardé et changement de périphérique en cours de partie.

### Terra — gameplay et simulation serveur

**Écriture future autorisée** : `ServerScriptService/Services/`, définitions métier et tests de simulation. Modifications des types partagés proposées à Sol, sans édition concurrente.

**Mission** : phases et temps serveur, IA clients et patience, tables/commandes, recettes/cuisson/brûlage/lavage/déchets, automatisation, recherche/plans, cartes/franchises côté règles et génération de grille.

**Livrables** : machines à états et modules de domaine, catalogue source/version, invariants de propriété des objets, simulateur déterministe, scénarios d’intégration et matrice des divergences à PlateUp!.

**Acceptation** : conservation des objets, aucune double livraison ou double recette économique, transferts atomiques, service restant actif tant que les clients restants ne sont pas traités, sélection de cartes aux bonnes frontières et génération toujours validée ou remplacée par le secours. Les minuteries n’utilisent pas le framerate client.

### Sol — infrastructure / sécurité / persistance

**Écriture future autorisée** : `ServerScriptService/Infrastructure/`, bootstraps, `Shared/Types`, `Shared/Protocol`, enregistrement des Remotes, adaptateurs de sauvegarde et tests de charge/sécurité. Les changements de types sont annoncés à Luna/Terra.

**Mission** : validation commune, routage RemoteEvents, profils et migrations, checkpoints, verrou de session, consommation idempotente de franchises, instrumentation, nettoyage des ressources et optimisation mesurée.

**Livrables** : modules réseau/persistance/sécurité, schémas versionnés, documentation des limites et erreurs, tests de panne/concurrence, rapport de charge avec environnement et métriques. Pooling seulement si le profilage le justifie.

**Acceptation** : aucune écriture d’un ancien détenteur de bail ; aucun profil vierge sauvegardé après erreur de lecture ; franchise consommée au plus une fois avec run récupérable ; refus des payloads invalides ; absence de croissance mémoire non bornée sur sessions prolongées.

## 3. Standards Luau

- `--!strict` en première ligne des scripts et modules de production.
- Types explicites pour interfaces publiques, états, intentions, résultats et données persistées. Unions discriminées pour actions et états.
- `PascalCase` pour services, modules, contrôleurs et types ; `camelCase` pour variables, paramètres et fonctions ; `UPPER_SNAKE_CASE` pour constantes immuables.
- Éviter `any` ; utiliser `unknown` aux frontières puis valider. Toute exception de typage est justifiée localement.
- Éviter globals implicites, dépendances circulaires, mutations cachées et accès directs aux internes d’un autre service.
- Modules de domaine testables sans Instances quand possible ; injection d’horloge, RNG et persistance pour les tests.
- Aucun yield dans une section atomique d’achat, transfert ou mutation d’état. Pas de requête DataStore dans le tick gameplay.
- Nettoyer connexions, tâches et objets à la fin d’une run ; pas de boucle par objet si un ordonnanceur partagé suffit.
- Ne pas employer `task.wait()` comme horloge de progression ; calculer à partir du temps serveur écoulé.
- Secrets et décisions autoritaires hors `ReplicatedStorage`. Aucun asset/script téléchargé exécuté sans revue.
- Commentaires sur les invariants et compromis, pas sur les évidences du code.

## 4. Contrat réseau — RemoteEvents uniquement

Tous les échanges applicatifs client-serveur passent par les événements ci-dessous ; pas de `RemoteFunction`/`InvokeServer`. La réplication native des représentations Roblox ne remplace pas le protocole métier.

### Enveloppes versionnées

Notation de contrat, non code déjà créé :

| RemoteEvent | Direction | Champs principaux |
| --- | --- | --- |
| `ActionRequest` | client → serveur | `protocolVersion`, `runId`, `requestId`, `action`, `expectedEntityRevisions`, `payload` |
| `ActionResult` | serveur → demandeur | `requestId`, `status`, `code`, `committedRevision` |
| `StateDelta` | serveur → participants | `runId`, `baseRevision`, `revision`, `changes` |
| `SnapshotRequest` | client → serveur | `protocolVersion`, `runId`, `lastRevision` |
| `StateSnapshot` | serveur → client | `runId`, `snapshotId`, `revision`, `chunkIndex`, `chunkCount`, `stateChunk` |

Les intentions sont une liste fermée : `PickUp`, `PutDown`, `BeginWork`, `EndWork`, `TakeOrder`, `Serve`, `PlaceAppliance`, `RotateAppliance`, `BuyBlueprint`, `RerollBlueprints`, `ConfigureMachine`, `VoteCard`, `SetReady`. Ajouter une action exige schéma, permissions et tests.

Exemples :

- Four : `BeginWork { applianceId, interactionKind }` ; le serveur vérifie contenu, portée et recette. Il calcule seul cuisson et brûlage.
- Assiette : `PutDown { targetEntityId, slotId }` ; le serveur déduit l’objet tenu, vérifie compatibilité et transfère source/destination atomiquement.
- Placement : `PlaceAppliance { applianceId, cellX, cellZ, rotation }` ; coordonnées entières bornées et rotation dans quatre valeurs. Pas de `CFrame` arbitraire faisant autorité.

### Traitement obligatoire

1. Utiliser le `Player` fourni par Roblox ; jamais un `userId` client pour décider de l’auteur.
2. Valider version, forme, types, profondeur, longueurs, nombres finis et bornes avant calcul coûteux.
3. Vérifier participation, droits, phase, portée calculée serveur, état des mains, occupation et ressources. Contrôler aussi les déplacements impossibles, le personnage pouvant être simulé par le client.
4. Dédupliquer par session/joueur/`requestId`. Un doublon identique retourne le résultat mémorisé ; même identifiant avec payload différent est refusé.
5. Vérifier les révisions des entités touchées, pas nécessairement toute la run. Sérialiser les mutations en concurrence.
6. Appliquer la mutation sans yield ; publier le delta et l’ack portant la révision validée.
7. Ne pas rejouer une action si son ack tarde : renvoyer le même identifiant, puis resynchroniser.

Codes minimaux : `InvalidPayload`, `RateLimited`, `NotParticipant`, `WrongPhase`, `OutOfRange`, `StaleRevision`, `Occupied`, `InsufficientFunds`, `InvalidRecipe`, `PersistenceUnavailable`, `ProtocolMismatch`.

Les résultats d’actions et les deltas peuvent arriver dans des ordres différents : l’UI corrèle par identifiant et révision. Si une base de delta manque, demander un snapshot ; pendant l’assemblage, buffer borné puis appliquer uniquement les deltas postérieurs contigus. Snapshot incomplet/expiré : abandon et nouvelle demande limitée. Ne jamais fusionner des chunks de snapshots différents. Filtrer toute donnée privée.

### Budgets applicatifs initiaux

- 10 intentions/s/joueur, burst 20, ajustables après mesure ; limites distinctes plus strictes pour relances, votes et snapshots.
- Payload d’intention ≤ 4 Kio estimés, profondeur ≤ 4, chaînes et listes bornées par action ; validation structurelle avant sérialisation éventuelle.
- Delta/chunk ≤ 4 Kio cible ; snapshot initial ≤ 32 Kio cible, découpé si nécessaire. Ce ne sont pas les limites de la plateforme.
- Cache de déduplication borné ; identifiants monotones par session et fenêtre de validité pour empêcher la réexécution après éviction. Les transactions persistantes gardent leur identifiant durable indépendamment de ce cache.
- Ne jamais envoyer une requête par frame pour maintenir une interaction ; début/fin et expiration serveur suffisent.

## 5. Persistance et modèle de propriété

Un profil propriétaire contient `schemaVersion`, `meta`, `franchises`, `activeRun`, `recentTransactions` et `sessionLease`. `activeRun` contient notamment `runId`, argent de run, checkpoint et version des règles. Pas de monnaie permanente ajoutée par défaut.

L’hôte possède la run ; les invités n’en possèdent pas des copies. Déconnexion de l’hôte : suspendre puis reprendre/fermer selon délai produit configurable, sans transférer silencieusement la propriété. Une migration de propriété éventuelle nécessite un contrat séparé.

- Consommer une franchise et créer la run dans le même `UpdateAsync` sur la même clé.
- Reprise après panne via le même `runId`/transactionId ; éviter double consommation et perte sans run récupérable.
- Franchise créée à la fermeture : transaction idempotente ; valider admissibilité et cartes avant écriture.
- Pas de garantie atomique entre profils ou clés. Les récompenses d’invités éventuelles demandent des reçus idempotents séparés.
- Bail proposé : renouvellement 30 s, expiration 90 s ; sauvegardes ordinaires regroupées avec renouvellement si possible pour ne pas multiplier les écritures.
- Jeton de fencing strictement croissant à la reprise. Chaque écriture vérifie propriétaire et jeton ; l’ancien serveur cesse les mutations dès perte de propriété ou absence de renouvellement sûr.
- Callback `UpdateAsync` pur : aucune émission de RemoteEvent, aucun crédit extérieur, aucun yield ; il peut être rappelé.
- Réessais bornés, backoff/jitter, contrôle du budget et état UI explicite. Si une transaction critique échoue, rester dans une phase sûre et ne pas annoncer de succès durable.
- Ne pas compter sur `BindToClose` seul. Sauvegarder aux transitions et expliquer la reprise au dernier checkpoint, avec risque de perte du service non checkpointé.

Les tests de persistance utilisent un environnement dédié, jamais les profils de production.

## 6. Definition of Done avant fusion

Pour chaque sous-système :

1. Exigence reliée à `agent.md`, source wiki ou adaptation identifiée.
2. Contrat typé publié, responsabilités claires et aucune modification hors périmètre sans accord.
3. Analyse Luau sans nouvelle erreur ; formatage et lint selon les outils choisis à l’initialisation du projet.
4. Tests unitaires des règles et tests d’intégration des frontières ; résultats et commande/méthode consignés.
5. Tests de refus et de concurrence, pas seulement le chemin heureux.
6. Aucune confiance dans argent, temps, résultat de recette, inventaire ou position fournis par le client.
7. Mesures de performance du scénario concerné, nettoyage vérifié et logs sans secrets/données personnelles inutiles.
8. Revue par un autre rôle et validation de l’orchestrateur ; aucune mention « testé » sans preuve d’exécution.
9. Toute migration persistante possède tests ancien/nouveau format et stratégie de reprise ; rollback de code compatible avec les données ou bloqué explicitement.

### Matrice minimale de recette

| Sous-système | Cas bloquants avant fusion |
| --- | --- |
| Placement/génération | chevauchement, sortie inaccessible, chaise isolée, seed invalide, conflit entre deux joueurs |
| Cuisine | double prise, interruption, cuisson prête/brûlée, objet incompatible, lavage et élimination sans duplication |
| Automatisation | conveyor ne tire pas, sortie occupée, deux sources, boucle saturée, prise joueur simultanée, filtre exact, extraction intermédiaire |
| Clients | capacité du plus grand groupe, petit groupe dépassant grand, priorité d’accueil, patience partagée extérieure, fin chrono avec clients présents |
| Recherche | cabinet diagonal accepté, pièce différente refusée, quotas malgré plusieurs bureaux, remise arrondie, copie non recopiable, plans au sol détruits |
| Cartes/jours | débuts J4/J7/J10/J13/J16, décoration J6/J11/J16, J15 terminé, carte franchise sans effet sur run courante |
| Franchises | prérequis des trois cartes, héritage, consommation répétée, échec entre lancement et confirmation, reprise même run |
| Réseau | payload malformé/NaN/infini/surdimensionné, spam, intention répétée/périmée, delta manquant, snapshot fragmenté |
| Persistance | throttling, lecture en échec, callback rejoué, deux serveurs, bail expiré, ancien serveur écrivant tard, migration |
| UX | PC/mobile/manette, focus, zones sûres, refus retardé, reconnexion, perte d’ack, alertes sans couleur ni son |
| Charge | 4 joueurs, 200 appareils, 300 objets, 40 clients ; durée 30 min ; tick p95, FPS, trafic, mémoire et connexions |

Les limites de charge sont des cibles initiales définies dans `agent.md`, pas une autorisation de tronquer la demande de clients en pleine run. Tester aussi les comportements de dépassement contrôlé.

## 7. Livraisons séquentielles et portes de validation

| Lot | Responsable | Dépendances | Porte de sortie |
| --- | --- | --- | --- |
| L0 — parcours et données | Luna | vision `agent.md` | wireframes, commandes, erreurs, liste de données |
| T0 — règles et états | Terra | L0 | machines à états, invariants, sources et scénarios |
| S0 — protocole et durabilité | Sol | L0 + T0 | schémas, limites, propriété, transactions et plan de tests |
| G0 — gel des interfaces | Orchestrateur | L0/T0/S0 | désaccords résolus, versions approuvées |
| S1 — socle minimal | Sol | G0 | bootstraps, transport validé, adaptateurs testables |
| T1 — vertical slice | Terra | S1 | boucle jouable, cuisine/service/nettoyage, tests métier |
| L1 — intégration | Luna | T1 | boucle accessible sur trois familles de périphériques |
| T2/S2/L2 — extensions par passages | Terra puis Sol puis Luna | slice validée | automatisation, recherche, run 15 jours, franchises |
| G1 — recette | Orchestrateur | tous les lots | rapport fidelity/sécurité/performance, réserves visibles |

Chaque passage est une tâche bornée avec propriétaire unique ; pas de trois agents éditant les mêmes fichiers. Les phases documentaires n’autorisent pas implicitement l’implémentation du prochain lot.

## 8. Validation de ce contrat

Contrat cohérent avec l’autorité serveur, les RemoteEvents exclusifs, les budgets proposés et la séparation run/métaprogression. Les dossiers et outils décrits restent à créer après choix du workflow source. Aucune validation Luau/Studio n’est applicable aux deux seuls documents produits ; les tests listés sont des exigences futures, non des résultats.
