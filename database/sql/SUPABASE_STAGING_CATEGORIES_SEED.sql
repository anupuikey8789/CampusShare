-- CampusShare staging only. Review before running manually in the staging SQL Editor.
-- This script inserts only the verified categories.name column. The verified schema
-- generates categories.id and defaults categories.created_at; existing IDs/references
-- are never updated or replaced.
--
-- Exact duplicates are ignored by the existing unique constraint on categories.name.
-- Case/outer-whitespace equivalent existing names are also left untouched.

BEGIN;

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
INSERT INTO public.categories (name)
SELECT approved.name
FROM approved
WHERE NOT EXISTS (
    SELECT 1
    FROM public.categories AS existing
    WHERE lower(btrim(existing.name)) = lower(btrim(approved.name))
)
ON CONFLICT (name) DO NOTHING;

COMMIT;
