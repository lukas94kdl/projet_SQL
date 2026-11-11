USE ecommerce;

-- Co-achats : paires de produits distincts presentes dans une meme commande.
-- Les commandes annulees sont exclues et une paire est ordonnee par identifiant.
SELECT
  p1.product_name AS produit_1,
  p2.product_name AS produit_2,
  COUNT(DISTINCT oi1.order_id) AS commandes_communes
FROM order_items AS oi1
JOIN order_items AS oi2
  ON oi2.order_id = oi1.order_id
  AND oi1.product_id < oi2.product_id
JOIN orders AS o ON o.order_id = oi1.order_id
JOIN products AS p1 ON p1.product_id = oi1.product_id
JOIN products AS p2 ON p2.product_id = oi2.product_id
WHERE o.status IN ('paid', 'shipped', 'delivered')
GROUP BY oi1.product_id, oi2.product_id, p1.product_name, p2.product_name
HAVING COUNT(DISTINCT oi1.order_id) >= 3
ORDER BY commandes_communes DESC, produit_1, produit_2
LIMIT 25;

-- Classement des clients a l'interieur de leur ville.
WITH customer_sales AS (
  SELECT
    c.customer_id,
    c.city,
    c.email,
    SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct)) AS revenue
  FROM customers AS c
  JOIN orders AS o ON o.customer_id = c.customer_id
  JOIN order_items AS oi ON oi.order_id = o.order_id
  WHERE o.status IN ('paid', 'shipped', 'delivered')
  GROUP BY c.customer_id, c.city, c.email
)
SELECT
  city,
  email,
  ROUND(revenue, 2) AS chiffre_affaires,
  RANK() OVER (PARTITION BY city ORDER BY revenue DESC) AS rang_dans_la_ville
FROM customer_sales
ORDER BY city, rang_dans_la_ville, email;
