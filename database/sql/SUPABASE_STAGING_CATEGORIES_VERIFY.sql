-- Read-only CampusShare staging verification. Run after reviewing/running the seed SQL.
-- This reports only category records and contains no user profile or secret data.

WITH approved(name) AS (
    VALUES
        ('Study Materials'),
        ('Books'),
        ('Documents'),
        ('Digital Resources'),
        ('Tutoring & Peer Help'),
        ('Study Groups & Projects'),
        ('Equipment & Electronics'),
        ('Stationery & Supplies'),
        ('Opportunities'),
        ('Campus Life & Events'),
        ('Housing & Essentials'),
        ('Announcements & Lost & Found')
)
SELECT
    approved.name AS approved_name,
    matched.id,
    matched.name AS stored_name,
    matched.created_at,
    CASE
        WHEN matched.id IS NULL THEN 'MISSING'
        WHEN matched.name = approved.name THEN 'OK'
        ELSE 'EXISTING EQUIVALENT NAME; PRESERVED'
    END AS verification
FROM approved
LEFT JOIN LATERAL (
    SELECT category.id, category.name, category.created_at
    FROM public.categories AS category
    WHERE lower(btrim(category.name)) = lower(btrim(approved.name))
    ORDER BY category.id
    LIMIT 1
) AS matched ON true
ORDER BY approved.name;

-- Optional read-only check for pre-existing case/whitespace-equivalent duplicates.
SELECT lower(btrim(name)) AS normalized_name, count(*) AS matching_rows
FROM public.categories
GROUP BY lower(btrim(name))
HAVING count(*) > 1
ORDER BY normalized_name;
