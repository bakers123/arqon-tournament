# ARQON security hardening — audit and rollout plan

Branch: `security/admin-roles-foundation`
Base: `main`
Scope: additive preparation only. No production database changes have been applied.

## Confirmed findings

1. `index.html` embeds an administrator credential in client-side JavaScript (`ADMIN_KEY`) and grants administrator UI access when the URL query parameter `admin` matches it. Anything shipped to a browser is public; this is not authentication.
2. The Supabase security advisor reports RLS disabled on:
   - `public.access_codes`
   - `public.players`
   - `public.drafts`
   The tables have permissive policies but RLS is off, so those policies do not protect the data.
3. The advisor also reports broad anonymous-access policies on application tables including `messages`, `news`, `results`, `schedule`, `sponsors`, and `tournament`.
4. Current player onboarding depends on anonymous Supabase Auth sessions, a lookup in `access_codes`, inserting/updating `players`, and deleting the consumed code. Draft/chat features also use player sessions.
5. Public pages read tournament, schedule, results, news, sponsors and player data. These read paths must remain available where intended.

## Required target design

- Individual Supabase Auth accounts for organizers; no shared client-side password.
- Server/database-backed organizer roles: `owner`, `admin`, `editor`.
- Authorization must be enforced by database RLS, not by hiding UI controls.
- Keep player one-time-code onboarding and anonymous player sessions working, but move code redemption into a narrowly scoped trusted server-side operation. Do not expose a table-wide ability to enumerate, insert, or delete access codes.
- Public read access should be limited to the exact published data needed by public pages.
- Organizer write access should be granted only to authenticated users with an appropriate role.
- Never put a Supabase service-role/secret key in browser code.

## Safe rollout sequence

1. Replace URL-key administrator detection with Supabase Auth and role lookup. Add organizer sign-in UI and role-aware UI gating.
2. Add a private organizer-role table and controlled role-management workflow. Bootstrap the first owner through the Supabase dashboard, not a public signup path.
3. Implement a trusted one-time-code redemption endpoint that atomically validates/consumes a code and binds the player session. Preserve existing player records.
4. Add explicit least-privilege RLS policies table by table, including read policies for public pages and player-specific policies for drafts/chat.
5. Test anonymous player login, code redemption, draft reads/writes, chat, public tournament pages, and organizer CRUD using separate anon/player/organizer sessions.
6. Only after those tests pass, remove legacy permissive policies and the old URL-key path.

## Do not do yet

- Do not simply enable RLS on the three disabled tables: the existing client would lose access and player onboarding would fail.
- Do not drop or truncate tables, rotate keys, or delete existing access codes/player rows as part of this preparation.
- Do not add a client-side role flag or trust `user_metadata` for authorization.

## Verification snapshot

The Supabase project inspection on 2026-11-02 found the three RLS-disabled tables listed above. The security advisor additionally flagged anonymous-access policies and disabled leaked-password protection. Re-run the advisor after each rollout stage.
