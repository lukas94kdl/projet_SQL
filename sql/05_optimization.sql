USE ecommerce;

-- Plan de la requete mensuelle : observer les acces aux commandes et aux lignes.
EXPLAIN
SELECT
  DATE_FORMAT(o.order_date, '%Y-%m-01') AS sales_month,
  SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct)) AS revenue
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.order_id
WHERE o.status IN ('paid', 'shipped', 'delivered')
  AND o.order_date >= '2024-01-01'
  AND o.order_date < '2026-01-01'
GROUP BY DATE_FORMAT(o.order_date, '%Y-%m-01');

-- Plan d'une recherche de co-achats par produit.
EXPLAIN
SELECT oi1.product_id, oi2.product_id, COUNT(DISTINCT oi1.order_id) AS orders_together
FROM order_items AS oi1
JOIN order_items AS oi2
  ON oi2.order_id = oi1.order_id
  AND oi1.product_id < oi2.product_id
WHERE oi1.product_id = 1
GROUP BY oi1.product_id, oi2.product_id;

-- Index disponibles pour les jointures et filtres utilises dans les exemples.
SHOW INDEX FROM orders;
SHOW INDEX FROM order_items;
