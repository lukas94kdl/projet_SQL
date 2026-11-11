USE ecommerce;

-- 1. Chiffre d'affaires global et nombre de commandes payees ou expediees.
SELECT
  COUNT(DISTINCT o.order_id) AS nombre_commandes,
  ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct)), 2) AS chiffre_affaires
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.order_id
WHERE o.status IN ('paid', 'shipped', 'delivered');

-- 2. Clients les plus rentables. La sous-requete calcule le CA au niveau client.
SELECT
  c.customer_id,
  CONCAT(c.first_name, ' ', c.last_name) AS client,
  c.email,
  ROUND(customer_sales.revenue, 2) AS chiffre_affaires
FROM customers AS c
JOIN (
  SELECT
    o.customer_id,
    SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct)) AS revenue
  FROM orders AS o
  JOIN order_items AS oi ON oi.order_id = o.order_id
  WHERE o.status IN ('paid', 'shipped', 'delivered')
  GROUP BY o.customer_id
) AS customer_sales ON customer_sales.customer_id = c.customer_id
ORDER BY customer_sales.revenue DESC
LIMIT 20;

-- 3. CTE mensuelle et variation par rapport au mois precedent.
WITH monthly_sales AS (
  SELECT
    DATE_FORMAT(o.order_date, '%Y-%m-01') AS sales_month,
    SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct)) AS revenue
  FROM orders AS o
  JOIN order_items AS oi ON oi.order_id = o.order_id
  WHERE o.status IN ('paid', 'shipped', 'delivered')
  GROUP BY DATE_FORMAT(o.order_date, '%Y-%m-01')
),
monthly_comparison AS (
  SELECT
    sales_month,
    revenue,
    LAG(revenue) OVER (ORDER BY sales_month) AS previous_month_revenue
  FROM monthly_sales
)
SELECT
  sales_month,
  ROUND(revenue, 2) AS chiffre_affaires,
  ROUND(previous_month_revenue, 2) AS chiffre_affaires_mois_precedent,
  ROUND(
    100 * (revenue - previous_month_revenue)
      / NULLIF(previous_month_revenue, 0),
    2
  ) AS evolution_pct
FROM monthly_comparison
ORDER BY sales_month;

-- 4. Classement des produits et part du CA de leur categorie.
WITH product_sales AS (
  SELECT
    p.product_id,
    p.product_name,
    c.category_name,
    SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct)) AS revenue
  FROM products AS p
  JOIN categories AS c ON c.category_id = p.category_id
  JOIN order_items AS oi ON oi.product_id = p.product_id
  JOIN orders AS o ON o.order_id = oi.order_id
  WHERE o.status IN ('paid', 'shipped', 'delivered')
  GROUP BY p.product_id, p.product_name, c.category_name
)
SELECT
  category_name,
  product_name,
  ROUND(revenue, 2) AS chiffre_affaires,
  RANK() OVER (PARTITION BY category_name ORDER BY revenue DESC) AS rang_categorie,
  ROUND(
    100 * revenue / NULLIF(SUM(revenue) OVER (PARTITION BY category_name), 0),
    2
  ) AS part_du_ca_categorie_pct
FROM product_sales
ORDER BY category_name, rang_categorie, product_name;

-- 5. CTE et somme cumulative du CA mensuel.
WITH monthly_sales AS (
  SELECT
    DATE_FORMAT(o.order_date, '%Y-%m-01') AS sales_month,
    SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct)) AS revenue
  FROM orders AS o
  JOIN order_items AS oi ON oi.order_id = o.order_id
  WHERE o.status IN ('paid', 'shipped', 'delivered')
  GROUP BY DATE_FORMAT(o.order_date, '%Y-%m-01')
)
SELECT
  sales_month,
  ROUND(revenue, 2) AS chiffre_affaires_mensuel,
  ROUND(SUM(revenue) OVER (
    ORDER BY sales_month
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ), 2) AS chiffre_affaires_cumule
FROM monthly_sales
ORDER BY sales_month;
