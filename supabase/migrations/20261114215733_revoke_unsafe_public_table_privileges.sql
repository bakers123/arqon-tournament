-- Keep public reads and authenticated RLS-checked CRUD intact.
-- Remove direct anonymous writes and operations that bypass row-level security.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
ON ALL TABLES IN SCHEMA public FROM anon;

-- TRUNCATE bypasses RLS, so authenticated client sessions must not hold it either.
-- REFERENCES and TRIGGER are not needed by browser clients.
REVOKE TRUNCATE, REFERENCES, TRIGGER
ON ALL TABLES IN SCHEMA public FROM authenticated;
