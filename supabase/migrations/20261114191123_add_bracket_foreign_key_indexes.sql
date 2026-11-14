-- Add indexes for foreign keys flagged by the Supabase performance advisor.
-- These indexes support FK checks and common bracket/assignment lookups.

create index if not exists bracket_assignments_assigned_by_idx
  on public.bracket_assignments (assigned_by);

create index if not exists bracket_assignments_bracket_id_idx
  on public.bracket_assignments (bracket_id);

create index if not exists bracket_audit_actor_id_idx
  on public.bracket_audit (actor_id);

create index if not exists bracket_documents_created_by_idx
  on public.bracket_documents (created_by);

create index if not exists bracket_documents_updated_by_idx
  on public.bracket_documents (updated_by);
