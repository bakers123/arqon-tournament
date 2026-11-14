-- Anonymous clients cannot write to public tables, so they do not need sequence privileges.
-- Keep authenticated sequence access for RLS-protected organizer/player inserts.
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
