-- 0001_init.sql — demo schema.
-- Migrations are idempotent (CREATE ... IF NOT EXISTS) so the migrate Job can
-- re-run safely; the Job applies every /migrations/*.sql in filename order.
CREATE TABLE IF NOT EXISTS demo_items (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
