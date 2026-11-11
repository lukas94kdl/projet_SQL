USE ecommerce;

SET SESSION cte_max_recursion_depth = 10000;

INSERT IGNORE INTO categories (category_id, category_name) VALUES
  (1, 'Maison'),
  (2, 'Cuisine'),
  (3, 'Informatique'),
  (4, 'Audio'),
  (5, 'Mode'),
  (6, 'Sport'),
  (7, 'Jardin'),
  (8, 'Livres'),
  (9, 'Jouets'),
  (10, 'Beaute'),
  (11, 'Bureau'),
  (12, 'Voyage');

INSERT IGNORE INTO customers
  (customer_id, first_name, last_name, email, city, created_at)
WITH RECURSIVE sequence_ids (n) AS (
  SELECT 1
  UNION ALL
  SELECT n + 1 FROM sequence_ids WHERE n < 400
)
SELECT
  n,
  CONCAT('Prenom', LPAD(n, 4, '0')),
  CONCAT('Client', LPAD(n, 4, '0')),
  CONCAT('client', n, '@example.test'),
  CASE MOD(n, 6)
    WHEN 0 THEN 'Paris'
    WHEN 1 THEN 'Lyon'
    WHEN 2 THEN 'Lille'
    WHEN 3 THEN 'Nantes'
    WHEN 4 THEN 'Bordeaux'
    ELSE 'Toulouse'
  END,
  DATE_ADD('2022-01-01', INTERVAL MOD(n * 19, 730) DAY)
FROM sequence_ids;

INSERT IGNORE INTO products (product_id, category_id, product_name, price, active)
WITH RECURSIVE sequence_ids (n) AS (
  SELECT 1
  UNION ALL
  SELECT n + 1 FROM sequence_ids WHERE n < 60
)
SELECT
  n,
  MOD(n - 1, 12) + 1,
  CONCAT('Produit ', LPAD(n, 3, '0')),
  CAST(5 + MOD(n * 17, 196) AS DECIMAL(10, 2)),
  MOD(n, 15) <> 0
FROM sequence_ids;

INSERT IGNORE INTO orders (order_id, customer_id, order_date, status)
WITH RECURSIVE sequence_ids (n) AS (
  SELECT 1
  UNION ALL
  SELECT n + 1 FROM sequence_ids WHERE n < 1800
)
SELECT
  n,
  MOD(n * 73, 400) + 1,
  DATE_ADD('2024-01-01', INTERVAL MOD(n * 17, 730) DAY)
    + INTERVAL MOD(n * 11, 86400) SECOND,
  CASE
    WHEN MOD(n, 10) = 0 THEN 'cancelled'
    WHEN MOD(n, 3) = 0 THEN 'delivered'
    WHEN MOD(n, 3) = 1 THEN 'paid'
    ELSE 'shipped'
  END
FROM sequence_ids;

INSERT IGNORE INTO order_items
  (order_id, product_id, quantity, unit_price, discount_pct)
WITH RECURSIVE sequence_ids (n) AS (
  SELECT 1
  UNION ALL
  SELECT n + 1 FROM sequence_ids WHERE n < 7200
)
SELECT
  FLOOR((n - 1) / 4) + 1,
  MOD((FLOOR((n - 1) / 4) + 1) * 7 + MOD(n - 1, 4) * 13, 60) + 1,
  MOD(n * 13, 4) + 1,
  p.price,
  CAST(MOD(n * 7, 6) * 0.05 AS DECIMAL(4, 3))
FROM sequence_ids
JOIN products AS p
  ON p.product_id = MOD((FLOOR((n - 1) / 4) + 1) * 7 + MOD(n - 1, 4) * 13, 60) + 1;
