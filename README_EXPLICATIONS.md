# Guide d'explication du projet

Ce document accompagne le [guide de démarrage](./README.md). Il explique le
but du projet, le rôle de chaque fichier et les décisions prises dans les
requêtes. Il s'adresse à une personne qui souhaite comprendre le code, le
présenter ou le faire évoluer.

## 1. But du projet

Ce projet pédagogique montre comment passer de données de commandes à des
indicateurs de ventes avec MySQL 8.4. Il sert à pratiquer :

- les jointures et agrégations (`JOIN`, `GROUP BY`, `SUM`, `COUNT`) ;
- les sous-requêtes et les expressions de table communes (`WITH`) ;
- les fonctions de fenêtre (`LAG`, `RANK`, `SUM() OVER`) ;
- les contraintes relationnelles, les index et la lecture d'un plan `EXPLAIN` ;
- le démarrage reproductible d'une base locale avec Docker Compose.

Les données sont entièrement synthétiques. Le projet est un support
d'apprentissage et une base de démonstration, pas un système de vente prêt à
recevoir des données réelles.

## 2. Vue d'ensemble des fichiers

| Fichier | Rôle |
|---|---|
| `compose.yaml` | Décrit le service MySQL, ses paramètres, son volume et son contrôle de santé. |
| `.env.example` | Donne des valeurs locales d'exemple pour le mot de passe et le port. |
| `.gitignore` | Évite d'ajouter le fichier `.env` local à Git. |
| `sql/01_schema.sql` | Crée la base, les tables, les relations, les contraintes et les index. |
| `sql/02_seed.sql` | Insère un jeu de données synthétique et déterministe. |
| `sql/03_progressive.sql` | Présente cinq analyses SQL, des agrégations aux fenêtres. |
| `sql/04_advanced.sql` | Recherche des co-achats et classe les clients par ville. |
| `sql/05_optimization.sql` | Affiche des plans d'exécution et les index concernés. |

Au premier démarrage sur un volume vide, l'image MySQL exécute les fichiers
montés dans `/docker-entrypoint-initdb.d` par ordre de nom : schéma, données,
puis requêtes. Les scripts d'initialisation ne se relancent pas
automatiquement lorsque le volume contient déjà une base.

## 3. Modèle de données

```text
categories 1 ─── * products 1 ─── * order_items * ─── 1 orders * ─── 1 customers
```

- **`customers`** contient le profil de chaque client. L'adresse e-mail est
  unique.
- **`categories`** répertorie les familles de produits.
- **`products`** contient le prix catalogue courant et la catégorie d'un
  produit. `active` indique si le produit est proposé actuellement ; cela ne
  supprime pas son historique de ventes.
- **`orders`** relie un client à une date et à un statut de commande.
- **`order_items`** représente les produits et quantités d'une commande.
  `unit_price` conserve le prix au moment de la vente plutôt que de dépendre du
  prix catalogue, qui pourrait changer. `discount_pct` est une remise comprise
  entre 0 inclus et 1 exclu.

Le chiffre d'affaires utilisé dans les analyses correspond à la somme de
`quantity * unit_price * (1 - discount_pct)`. La définition inclut les commandes
`paid`, `shipped` et `delivered`, et exclut celles qui sont `pending` ou
`cancelled`. C'est une convention pédagogique : une comptabilité réelle peut
traiter différemment les expéditions, retours, remboursements et taxes.

### `sql/01_schema.sql` — structure et intégrité

Le script sélectionne `utf8mb4` pour stocker le texte, puis crée cinq tables
InnoDB. Les identifiants sont des clés primaires auto-incrémentées ; les clés
étrangères empêchent les commandes sans client ou les lignes associées à des
produits inexistants. Les contraintes `CHECK` valident le prix, les quantités,
la remise et les statuts autorisés.

Les index servent notamment aux relations fréquentes et aux filtres :

- `customers.email` et `categories.category_name` sont uniques ;
- `orders(customer_id, order_date)` aide à retrouver les commandes d'un client
  et celles ordonnées par date pour un client donné ;
- `orders(status, order_date)` peut aider à filtrer les commandes par statut et
  période ;
- `order_items(order_id, product_id)` empêche de répéter un même produit dans
  une commande et prend en charge les recherches par commande ;
- `order_items(product_id, order_id)` prend en charge les recherches inverses,
  par produit.

L'ordre des colonnes d'un index composé compte : MySQL peut généralement
exploiter un préfixe gauche de l'index. Un index n'est donc pas automatiquement
utile à toute requête qui mentionne l'une de ses colonnes.

### `sql/02_seed.sql` — données reproductibles

Les CTE récursives construisent des suites d'entiers et évitent de saisir
manuellement des centaines de lignes :

1. 12 catégories sont insérées avec des identifiants fixes ;
2. une suite de 1 à 400 produit des clients fictifs, des adresses réservées à
   l'exemple (`example.test`) et des villes répétées ;
3. une suite de 1 à 60 produit des articles répartis dans les catégories ;
4. une suite de 1 à 1 800 produit les commandes, avec dates et statuts calculés ;
5. une suite de 1 à 7 200 produit quatre lignes par commande, avec quantités et
   remises calculées.

Les calculs fondés sur `MOD()` rendent la génération stable : les mêmes
identifiants produisent les mêmes valeurs. `INSERT IGNORE` et les identifiants
fixes facilitent une nouvelle insertion dans les tables correspondantes, mais
ce mécanisme n'est pas une stratégie de migration ni un remplacement d'une base
de test propre. La profondeur de récursion de session est relevée pour autoriser
les suites de cette taille.

### `sql/03_progressive.sql` — analyses de base à intermédiaires

Toutes les requêtes commencent par sélectionner `ecommerce`. Les commentaires
les numérotent dans un ordre pédagogique :

1. **Indicateurs globaux.** Joint les commandes à leurs lignes, additionne le
   montant net de chaque ligne et compte les commandes distinctes. Le `COUNT
   (DISTINCT ...)` exprime que le résultat attendu est un nombre de commandes,
   même si chacune a plusieurs lignes.
2. **Clients les plus rentables.** Une sous-requête calcule le chiffre
   d'affaires par client ; le résultat est ensuite joint au profil client,
   trié et limité aux 20 premiers.
3. **Comparaison mensuelle.** `monthly_sales` regroupe le chiffre d'affaires
   par mois. La seconde CTE applique `LAG()` pour récupérer la valeur de la
   ligne précédente, donc celle du mois précédent présent dans le résultat.
   `NULLIF` évite une division par zéro dans le calcul du pourcentage.
4. **Produits par catégorie.** `product_sales` calcule le chiffre d'affaires
   de chaque produit. `RANK()` classe les produits à l'intérieur de leur
   catégorie ; `SUM() OVER (PARTITION BY ...)` calcule la base de comparaison
   de la part de chiffre d'affaires de chaque produit.
5. **Cumul mensuel.** La fenêtre `SUM() OVER` additionne les mois depuis le
   début de la série jusqu'au mois courant. Le cadre explicite `ROWS` documente
   le cumul attendu.

La série mensuelle ne contient que les mois qui ont des ventes admissibles.
Ainsi, `LAG()` compare au mois précédent **présent** dans la série, pas
nécessairement au mois calendaire précédent si un mois est absent.

### `sql/04_advanced.sql` — analyses complémentaires

- **Co-achats.** La table `order_items` est jointe à elle-même sur la commande.
  La condition `oi1.product_id < oi2.product_id` ordonne les identifiants :
  chaque paire est comptée une seule fois et un produit n'est pas associé à
  lui-même. La requête exclut les commandes annulées, regroupe les paires et
  conserve celles présentes dans au moins trois commandes.
- **Classement géographique.** Une CTE calcule le chiffre d'affaires de chaque
  client, puis `RANK()` classe les clients au sein de chaque ville. Les ex
  aequo partagent le même rang.

Le classement décrit une association, pas une preuve que les produits
s'influencent mutuellement. Un seuil fixe de trois commandes est un choix de
démonstration, pas une recommandation commerciale.

### `sql/05_optimization.sql` — examen des plans

Deux commandes `EXPLAIN` affichent le plan estimé pour :

1. une agrégation mensuelle filtrée par statut et période ;
2. une recherche de co-achats à partir du produit d'identifiant 1.

`SHOW INDEX` affiche les index disponibles sur les tables de commandes et de
lignes de commande. Pour étudier un plan, vérifiez entre autres les tables
parcourues, les index retenus, le type d'accès et le nombre de lignes estimé.
Un plan estimé n'est pas une mesure de temps réelle ; le choix de l'optimiseur
dépend de la taille et de la distribution des données.

### `compose.yaml`, `.env.example` et `.gitignore`

Compose utilise l'image MySQL 8.4, publie le port configurable sur la machine,
conserve les données dans le volume `mysql_data` et monte les scripts SQL en
lecture seule comme scripts d'initialisation. Le contrôle de santé attend que le
serveur MySQL réponde.

Pour personnaliser localement les paramètres, copier `.env.example` vers `.env`.
Le fichier `.gitignore` exclut ce dernier afin que la configuration locale ne
soit pas ajoutée au dépôt. Le mot de passe fourni est une valeur de
démonstration : il ne convient pas à un environnement partagé ou de production.

## 4. Parcours de lecture conseillé

1. Lire le modèle de données et les règles de calcul ci-dessus.
2. Examiner `01_schema.sql` pour comprendre les tables et leurs relations.
3. Suivre `02_seed.sql` et vérifier les volumes générés.
4. Exécuter `03_progressive.sql` dans l'ordre et observer la forme de chaque
   résultat.
5. Lire les deux analyses de `04_advanced.sql`, puis les plans de
   `05_optimization.sql`.
6. Modifier une seule hypothèse à la fois (filtre, période ou index), comparer
   le résultat, puis noter l'effet observé.

Les commandes de démarrage et de réinitialisation de la base sont documentées
dans le [guide principal](./README.md). La commande de réinitialisation avec
`docker compose down -v` supprime le volume et donc les données locales.

## 5. Axes d'amélioration

### A. Rendre les données plus réalistes

- Remplacer les règles périodiques de génération par des distributions avec
  saisonnalité, périodes promotionnelles, fréquences d'achat variables et
  catégories plus ou moins populaires.
- Ajouter des cas limites : clients sans commande, commandes sans statut
  finalisé, retours, annulations partielles et produits retirés du catalogue.
- Générer les données à partir d'une graine configurable et documenter les
  invariants attendus afin de conserver des tests reproductibles.
- Augmenter progressivement le volume pour mesurer des plans sur une charge
  proche de l'usage visé ; 1 800 commandes restent un petit jeu de démonstration.

### B. Préciser le modèle métier

- Définir sans ambiguïté à quel moment une vente devient du chiffre d'affaires
  (paiement, expédition ou livraison) et comment les retours et remboursements
  sont déduits.
- Ajouter, selon le besoin, taxes, frais de livraison, devise, adresse de
  livraison historisée et horodatages de changement de statut.
- Enregistrer les paiements et remboursements dans des tables dédiées plutôt
  que d'en déduire l'état financier du seul statut de la commande.
- Formaliser les transitions autorisées entre statuts. La contrainte actuelle
  vérifie les valeurs permises, pas l'historique de transition.
- Décider si une même référence produit peut être ajoutée plusieurs fois à une
  commande ; le schéma actuel impose une seule ligne par couple commande-produit.

### C. Améliorer les analyses

- Créer un calendrier de mois et le joindre aux ventes pour faire apparaître
  explicitement les mois sans vente. `LAG()` pourra alors comparer des mois
  calendaires consécutifs ; il faudra décider si un mois sans vente vaut zéro
  ou reste `NULL`.
- Distinguer ventes brutes, remises, taxes, retours et ventes nettes, puis
  centraliser la définition des indicateurs pour éviter des règles différentes
  d'une requête à l'autre.
- Enrichir les co-achats avec un support total, une proportion conditionnelle
  ou un indicateur tel que le lift. Protéger ces mesures contre les paires rares
  et valider les seuils sur des données adaptées.
- Comparer les classements par chiffre d'affaires à des mesures comme la marge,
  le nombre de commandes, le panier moyen et la récurrence.
- Prévoir des paramètres de période et des analyses par canal, région ou
  cohorte si ces attributs sont ajoutés au modèle.

### D. Vérifier et optimiser les performances

- Ajouter un jeu de tests automatisés qui vérifie les nombres de lignes, les
  clés étrangères, les statuts, la remise et quelques résultats analytiques
  connus.
- Comparer les plans avec des données plus volumineuses et l'usage réel avant
  d'ajouter ou supprimer des index. Chaque index accélère certains accès, mais
  consomme du stockage et peut ralentir les écritures.
- Sur une version compatible de MySQL et un jeu de test maîtrisé, compléter
  l'estimation `EXPLAIN` par `EXPLAIN ANALYZE`, qui exécute la requête ; ne pas
  le lancer sans tenir compte de son coût sur une requête lourde.
- Mesurer séparément le coût de `DATE_FORMAT` et du regroupement mensuel. Si
  cette analyse devient fréquente et coûteuse, envisager une table d'agrégats
  mensuels maintenue de manière contrôlée.
- Ajouter des index de couverture uniquement si les mesures justifient le coût
  supplémentaire ; éviter les index redondants.

### E. Renforcer l'exploitation et la sécurité

- Remplacer le compte `root` utilisé pour les exercices par un utilisateur
  applicatif avec des permissions limitées.
- Remplacer le mot de passe d'exemple, ne pas versionner `.env` et gérer les
  secrets hors du dépôt pour tout environnement partagé.
- Ajouter une stratégie de sauvegarde et de restauration ; un volume Docker
  assure la persistance locale mais ne constitue pas une sauvegarde.
- Fixer une politique de mise à jour et de sauvegarde de la version MySQL avant
  tout déploiement non local.
- Définir une règle de conservation et de protection des données avant de
  remplacer les exemples fictifs par des informations personnelles réelles.

## 6. Limites actuelles

- Le projet ne fournit pas d'application, d'API, de tableau de bord ni de
  migration de schéma versionnée.
- Les données synthétiques sont simples et ne démontrent pas à elles seules la
  performance sur un volume de production.
- Les analyses partagent une convention fixe de statuts pour calculer le
  chiffre d'affaires.
- Les requêtes d'optimisation affichent des plans estimés ; aucun benchmark
  chronométré n'est inclus.
- L'initialisation automatique est conçue pour un volume neuf, pas pour mettre
  à jour une base déjà créée.
