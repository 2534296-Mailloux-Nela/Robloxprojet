# Agent — Spécifications globales du projet

## 1. Statut et vision

Document de conception, version 0.1 — 29 octobre 2026. Aucune production Luau engagée. Le dépôt contient actuellement `projet4000.rbxl` et son verrou ; leur contenu n’a pas été inspecté ni modifié. L’arborescence ci-dessous est une cible, pas un inventaire existant.

Créer sur Roblox un jeu coopératif de restauration pour 1 à 4 joueurs, fidèle aux interactions et décisions systémiques de PlateUp! : préparation manuelle, pression du service, réorganisation de cuisine, automatisation et franchises. Public cible : joueurs Roblox appréciant coopération, optimisation et parties rejouables, avec onboarding accessible aux débutants.

La fidélité porte sur les règles, pas sur la copie du nom, des illustrations, sons, textes ou modèles de PlateUp!. Produire une identité et des assets originaux ; vérifier les droits avant publication. Pas d’achat payant de puissance ni de résurrection qui invaliderait les règles standard.

### Principes

- Serveur autoritaire ; le client présente et transmet des intentions.
- Actions simples, profondeur issue des interactions entre systèmes.
- Simulation déterministe à seed et entrées identiques pour faciliter le diagnostic.
- Contenu data-driven et versionné : recettes, cartes, appareils, prix et durées.
- Le wiki est la référence ; toute divergence est étiquetée comme adaptation Roblox.

## 2. Références et niveau de certitude

Pages consultées le 29 octobre 2026, via leur HTML :

| Source | Règles exploitées |
| --- | --- |
| https://wiki.plateupgame.com/ | Index et liens de référence |
| https://wiki.plateupgame.com/Automation | Poussée, extraction, filtres, blocages et conflits |
| https://wiki.plateupgame.com/Cards | Calendrier, choix, héritage et franchise |
| https://wiki.plateupgame.com/gameplay/DailyOperations | Préparation, service, overtime et décoration |
| https://wiki.plateupgame.com/gameplay/Customers | Groupes, tables, chemins, commandes et patience |
| https://wiki.plateupgame.com/gameplay/Research | Cabinets et bureaux |
| https://wiki.plateupgame.com/gameplay/Blueprints | Achat, conservation, copies et relances |

Faits vérifiés sur ces pages, non testés dans PlateUp! : règles détaillées ci-dessous. Les durées/prix non explicitement sourcés ne sont pas considérés comme validés. Les recettes exhaustives, appareils spécialisés et algorithmes exacts de génération nécessitent une recherche complémentaire avant implémentation.

Incertitudes explicites : le wiki ne donne pas l’arbitrage des convoyeurs concurrents ; certains exemples de durée du service et de patience extérieure sont ambigus. Ne pas transformer ces exemples en constantes définitives. Conserver une table de traçabilité `ruleId → source → version → test → éventuelle divergence` lors de la production.

## 3. Boucle de jeu

`Quartier général → sélection recette/plan/franchise → préparation → service → bilan → préparation suivante`.

La nuit/achat est une présentation de la phase de préparation, pas une phase de recherche séparée imposée par PlateUp!. Le nettoyage est principalement effectué pendant le service ; il ne doit pas être reporté gratuitement à une phase qui supprimerait la pression du jeu.

### Préparation / nuit

1. Afficher le bilan du service précédent, l’argent partagé et les choix dus au nouveau jour.
2. Choisir les cartes éventuelles, recevoir les plans, acheter et réorganiser les appareils.
3. Ranger les plans à conserver dans les cabinets ; les plans au sol disparaissent au début du service.
4. Configurer les machines et tester en mode entraînement.
5. Tous les participants actifs confirment « Prêt ». Toute modification structurante annule les confirmations.
6. Vérifier côté serveur tables, capacité du plus grand groupe, chaises accessibles, recette réalisable et placements avant démarrage.

L’entraînement est une simulation isolée : ni revenus, ni progression, ni consommations persistantes. Un groupe à la fois ne mesure pas le débit réel. Les réglages des Smart/Rotating Grabbers sont explicitement conservés à la sortie ; les stocks et plats de test sont réinitialisés.

### Service

- Générer les groupes selon jour, cartes et recette ; les accueillir puis prendre les commandes.
- Préparer, cuire, dresser, servir, débarrasser et laver ; gérer déchets et salissures.
- Exécuter recherche, copie et remise par interaction avec les bureaux pendant le service.
- La fin du chronomètre arrête les arrivées prévues, mais ne termine pas immédiatement la journée : traiter les clients restants.
- Une patience expirée entraîne la fermeture, sauf protection explicitement fournie par une règle active.

### Bilan

Calculer les revenus sur les événements de service autoritaires, sans récompense client. Valider la fin du jour une seule fois, produire un checkpoint, puis ouvrir la préparation. Après le jour 15 réussi : proposition de carte de franchise et poursuite possible en overtime.

## 4. Cuisine et entités

### Modèle de données

Chaque entité possède `entityId`, `kind`, `revision`, position logique, orientation et slots. Les Instances Roblox ne sont que la représentation de cet état.

- `FoodState` : recette, ingrédients, étapes acquises, cuisson, brûlage, portions et présentation. Une recette est un graphe de transformations avec préconditions, durée et résultats.
- `PlateState` : propre, garnie ou sale ; contenu référencé par identifiant. Ne pas encoder un plat complet seulement dans la couleur d’une Part.
- `ApplianceState` : définition, empreinte, entrée/sortie, slots, travail en cours, configuration et progression.
- `TableState` : chaises actives, groupe, commandes individuelles, plats livrés, phase de repas et vaisselle.
- `CustomerGroupState` : membres, destinations, service de repas, patience et état d’IA.
- `RunState` : seed, jour, phase, argent, cartes, thème, catalogue et participants.

Invariants : un objet appartient à exactement un conteneur (main, slot, table, stockage) ; pas de copie implicite ; une cuisson ne produit qu’une transformation ; seuls les événements autoritaires créditent la caisse.

### Actions

Prendre/poser, travailler, prendre une commande, servir, laver, jeter, interagir avec un bureau et configurer une machine. Une interaction maintenue utilise début/fin avec délai maximal, vérification régulière de portée et annulation à la déconnexion. Le client ne fournit jamais la durée de travail réalisée.

Les tables de cuisson suivent `Idle → Processing → Ready → Burnt` lorsque la recette/appareil autorise le brûlage. Le dépassement de cuisson et les exceptions sont définis dans les données. Lavage et préparation partagent un mécanisme de travail mais pas les mêmes règles métier.

## 5. Automatisation

### Règles de référence

- **Conveyor** : pousse vers sa sortie ; ne tire pas depuis la case précédente.
- **Grabber** : tire depuis son entrée lorsqu’il est vide, puis pousse vers sa sortie ; destination occupée = blocage, jamais écrasement.
- **Smart Grabber** : filtre sur l’objet et son état précis. Apprentissage par dépôt en entraînement/service ; reconfiguration possible, retour à un état sans filtre non prévu. Peut extraire un produit intermédiaire avant le traitement suivant lorsque le transfert est possible.
- **Rotating Grabber** : configuration d’entrée en préparation ; sortie ajustable en entraînement/service vers une des trois autres directions.
- Un traitement actif empêche normalement l’extraction ; appliquer explicitement les exceptions documentées du Smart Grabber.
- Mélangeurs, doseurs, portionneurs et autres appareils spécialisés : adapter le même système de slots et transformations ; compléter leurs fiches wiki avant d’activer leurs variantes.

### Adaptation technique Roblox

Grille logique avec orientation cardinale ; aucun déplacement de nourriture par physique libre. À chaque tick : calculer les propositions sur un état stable, résoudre les conflits, puis appliquer les transferts atomiquement. Un objet effectue au maximum un transfert par tick ; vitesse et intervalle sont paramétrables, à calibrer plutôt qu’à présenter comme exacts.

Arbitrage proposé : priorité tournante déterministe par destination, puis `entityId` pour départager. Cette règle est une adaptation, l’arbitrage original étant inconnu. Résoudre aussi les conflits avec les prises des joueurs. Les circuits saturés attendent sans détruire ni dupliquer leur contenu. Les animations clients interpolent les états confirmés.

Tests obligatoires : chaîne simple, sortie bloquée, boucle saturée, deux sources concurrentes, prise joueur simultanée, filtre d’état, cuisson intermédiaire et reconfiguration.

## 6. Clients et pression de service

Groupes initiaux de 1–2 clients, modifiables par cartes. Priorité d’accueil : table de repas, Hosting Stand, Coffee Table, file extérieure. Un petit groupe peut passer devant un grand si seule une petite table est disponible.

Navigation sur graphe de cases : entrée et chaque chaise active doivent être reliées. Ne pas dépendre uniquement du déplacement physique d’un Humanoid. Recalculer l’accessibilité lors des modifications de préparation ; vérifier les blocages dynamiques pertinents pendant le service.

Cycle : arrivée → file/accueil → table → réflexion → prise de commande → premier plat → complétion des plats → repas → service suivant éventuel → départ/débarrassage. La file extérieure utilise une jauge partagée ; les attentes à table dépendent de leur phase. Les valeurs exactes sont configurables et doivent être sourcées avant équilibrage final.

## 7. Plans, recherche et économie

Le « Blueprint Lab » désigne l’ensemble cabinets/bureaux et son UI, pas un laboratoire gratuit hors service.

- Achat de plans à la préparation ; améliorer un **plan**, jamais directement un appareil acheté.
- Cabinet dans une des huit cases voisines du bureau et dans la même pièce.
- Recherche pendant le service ; achat du résultat à la préparation suivante.
- Par cabinet et par jour : au maximum une amélioration, une remise et une copie, même avec plusieurs bureaux.
- Remise : division par deux, arrondi supérieur, minimum 1 ; conservée après amélioration.
- Une copie ne peut pas être recopiée.
- Boutique normalement de cinq plans, avec exceptions à représenter dans les données.
- Relance initiale de 10 pièces, puis +10 par utilisation à l’échelle de la partie ; plans en cabinet exclus.

Caisse partagée propre à la run. Aucun transfert automatique vers une monnaie permanente. Les achats concurrents sont sérialisés et idempotents. Déblocages permanents et franchises sont séparés de l’argent du restaurant.

## 8. Jours, cartes et franchises

- Objectif initial : réussir les jours 1 à 15, puis overtime sans limite artificielle de 15 jours.
- Première sélection au début du jour 4, puis tous les trois jours : 7, 10, 13, 16…
- Généralement un choix nourriture et un choix clientèle ; si une catégorie est épuisée, deux choix de l’autre catégorie.
- Décoration aux jours 6, 11, 16… ; thème choisi au jour 6, sauf thème hérité.
- Après réussite du jour 15 : choix d’une carte de franchise, sans effet sur la run en cours.
- À la fermeture d’une run admissible : conserver recette initiale, thème, héritage existant, nouvelle carte de franchise et trois cartes non-franchise acquises, en respectant les prérequis.
- Une franchise sauvegardée est consommée lors du lancement de la suivante. Le niveau de franchise n’ajoute pas de difficulté cachée ; les cartes expliquent les changements.

Représenter chaque carte par identifiant stable, catégorie, prérequis, exclusions, effets et règles d’héritage. Ordre d’application stable ; pas de scripts arbitraires fournis par le client. Tester les combinaisons incompatibles et le manque de candidats admissibles ; vérifier dans la référence le comportement des cas limites avant de figer un fallback.

Adaptation coopérative proposée : vote majoritaire pour les choix collectifs, égalité départagée par l’hôte avec délai visible. L’hôte possède la sauvegarde de run/franchise ; les invités ne reçoivent pas une copie de la franchise. Les récompenses personnelles éventuelles restent indépendantes, sans transaction multijoueur promise.

## 9. Génération procédurale

Adaptation proposée, non prétendue identique à l’algorithme PlateUp! : seed reproductible → enveloppe → pièces/portes → zones cuisine et salle → points d’entrée → équipement initial → validation.

Conserver une grille et un identifiant de pièce, utiles à la recherche et au placement. Valider connectivité, accès aux chaises, capacité, surfaces de préparation, source d’ingrédients, cuisson requise et lavage. Rejeter les seeds invalides avec un nombre borné de tentatives, puis utiliser un plan de secours testé. Enregistrer seed, version du générateur et modifications ; enregistrer aussi le layout effectif d’un checkpoint pour survivre aux changements de générateur.

## 10. Architecture Roblox cible

```text
ReplicatedStorage/
  Shared/Types, Protocol, Definitions, Grid, RecipeRules
  Remotes/ActionRequest, ActionResult, StateDelta, SnapshotRequest, StateSnapshot
ServerScriptService/
  Bootstrap.server.luau
  Services/RunService, InteractionService, KitchenService, AutomationService
  Services/CustomerService, BlueprintService, CardService, MapService
  Infrastructure/NetworkService, ProfileService, SecurityService, MetricsService
ServerStorage/
  Prefabs/Appliances, Customers, Food
StarterPlayer/StarterPlayerScripts/
  Bootstrap.client.luau
  Controllers/InputController, UIController, PlacementController, FeedbackController
StarterGui/
  Screens/HUD, Preparation, BlueprintShop, Cards, Summary
```

`RunService` métier sera importé sous un alias explicite pour éviter la confusion avec le service Roblox homonyme. Choisir ensuite un format source contrôlable en Git (Rojo ou export Studio) avant production ; ne pas éditer le binaire en parallèle.

**Serveur** : état canonique, économie, temps, IA, transferts, recettes, votes, placements et persistance. **Client** : saisies, caméra, UI, previews, interpolation et effets. **Shared** : types/données non secrets, sans autorité accordée au client.

RemoteEvents exclusivement pour la communication applicative client-serveur, y compris requêtes/réponses asynchrones et snapshots. Pas de RemoteFunctions. Contrat détaillé dans `contract.md`.

## 11. Sauvegarde et sûreté

Profil propriétaire versionné : déblocages, franchises, run active et identifiants de transactions dans une même clé lorsque leur atomicité est nécessaire. Une opération `UpdateAsync` réserve/consomme la franchise et crée la run récupérable ensemble. Échec de lancement : reprendre le même `runId`, pas consommer à nouveau.

Bail de session avec propriétaire, expiration et jeton de fencing ; toute écriture vérifie le jeton courant. Callbacks `UpdateAsync` sans effets externes. Réessais bornés avec backoff, budgets DataStore contrôlés et migrations de schéma testées. Ne jamais remplacer un profil illisible par un profil vierge sauvegardé.

Checkpoint aux frontières de jours et opérations critiques ; reprise au dernier checkpoint durable, pas promesse de reprise exacte à la frame. Suspendre toutes les mutations de la run dès perte du bail ou impossibilité de renouvellement sûr, pour éviter deux autorités concurrentes. Si seule la durabilité d’une transaction critique est indisponible alors que le bail reste valide, bloquer la transition ou la dépense concernée sans annoncer de succès durable. `PlayerRemoving`/`BindToClose` sont des derniers efforts, pas des garanties de sauvegarde.

## 12. UX et budgets techniques proposés

HUD : jour/phase, temps restant, argent partagé, commandes attachées aux tables, patience et jauges de traitement. Boutique : prix, prérequis, comparaison et raison d’un refus. Placement : grille, empreinte, orientation et états valide/interdit/en attente ; seul l’ack confirme le placement.

PC clavier/souris, mobile tactile sans survol, console navigation complète au focus. Prompts selon le périphérique actif ; actions critiques jamais distinguées seulement par couleur/son. Respecter les zones sûres, contraste lisible, textes adaptatifs et option de réduction des animations.

Budgets initiaux de recette, **objectifs à profiler et non limites Roblox** :

| Mesure | Cible initiale |
| --- | --- |
| Joueurs par restaurant | 1–4 |
| Grille maximale initiale | 32 × 32 cases |
| Appareils / objets manipulables / clients simulés | 200 / 300 / 40 |
| BaseParts actives du restaurant | ≤ 3 000, visuels simplifiés |
| Simulation logique | 10 Hz, temps en secondes serveur |
| Travail simulation p95 | ≤ 5 ms par tick sur scénario de charge |
| Rendu | ≥ 30 FPS mobile de référence ; 60 FPS PC cible |
| Deltas | 10 Hz maximum hors confirmations, regroupés |
| Trafic applicatif sortant | ≤ 30 Kio/s/joueur en régime normal |

Documenter les appareils physiques utilisés et les mesures ; l’émulateur Studio ne prouve pas les performances mobiles. Privilégier modèles ancrés, collision minimale, animations locales, nettoyage des connexions et pooling seulement après profilage. Si la capacité sûre est dépassée, refuser explicitement le lancement/placement plutôt que supprimer silencieusement clients ou commandes.

## 13. Périmètre et jalons

1. **Cadrage présent** : documents, sources, décisions et contrats ; aucun script de production.
2. **Vertical slice** : recette simple à spécifier, préparation/service, une table, cuisson, lavage, caisse et fermeture ; pas de promesse de clone complet à ce stade.
3. **Automatisation/recherche** : convoyeurs, grabbers, cabinets, bureaux et entraînement.
4. **Run complète** : cartes, décoration, jours 1–15, overtime, franchise et sauvegarde.
5. **Fidélité étendue** : catalogue de recettes/appareils, variantes, équilibrage et validation de chaque fiche source.
6. **Publication** : charge, exploit tests, accessibilité et assets originaux.

Ordre de passage des mandats : Luna → Terra → Sol, puis revue de l’orchestrateur. Les contrats réseau sont figés avant fusion de code ; le travail UI peut utiliser des mocks, jamais imposer une autorité client. Voir `contract.md` pour les responsabilités et portes de validation.

## 14. Validation documentaire

Couverture vérifiée : boucle, cuisine, automatisation, clients, recherche, progression, génération, réseau, persistance et multi-plateformes. Les règles sourcées sont séparées des propositions Roblox. Réserves ouvertes : constantes temporelles ambiguës, catalogue exhaustif, recette de la vertical slice, appareils de benchmark et fidélité des cas limites de franchise. Ces réserves bloquent les fonctions concernées, pas la rédaction du contrat. Aucun test Studio, réseau, DataStore ou gameplay n’a été exécuté à ce stade.
