# ARQON security hardening — rollout record

Repository: `bakers123/arqon-tournament`
Production branch: `main`
Scope: organizer authentication, player onboarding, and database access controls.

## Completed

- Removed the browser-shipped `ADMIN_KEY` and URL-query administrator bypass.
- Added organizer magic-link sign-in through Supabase Auth and private database roles: `owner`, `admin`, `editor`.
- Moved player code redemption to the authenticated `redeem-player-code` Edge Function and an atomic database function.
- Moved player-code issuance to an organizer-authorized database function.
- Moved player draft writes to a captain-validated RPC; participant IDs and match identity cannot be changed by player sessions.
- Added a public player directory projection that exposes names only.
- Enabled RLS on all application tables in the public schema and replaced permissive legacy policies with public-read / organizer-write or participant-specific policies.
- Kept existing tournament and player data in place.

## Production rollout status

- GitHub PR #1 merged to `main`.
- Supabase migrations for organizer roles, secure code redemption, least-privilege RLS, and player rebinding applied.
- Edge Function `redeem-player-code` is active with JWT verification enabled.
- Row counts were checked after rollout; existing rows remained present in players, access_codes, drafts, league_data, tournament, messages, news, and sponsors.

## Remaining operator steps

1. Invite the two intended organizer accounts in Supabase Dashboard → Authentication → Users.
2. Assign their rows in `private.organizer_roles` (first organizer: `owner`; second: `admin`). Do not create a public self-service role assignment endpoint.
3. Confirm the static website host publishes the current `main` branch. This repository change alone does not prove that a separate FTP/hosting account has deployed the files.
4. Run end-to-end smoke tests for public pages, player code redemption, both captains' draft actions, chat, and organizer CRUD.

## Notes

- No table was dropped or truncated, and no existing application rows were intentionally deleted.
- `public.player_directory` is a narrowly scoped view exposing only player names; the Supabase advisor flags its owner-rights view behavior for review.
- Security advisor warnings about SECURITY DEFINER functions are expected for the narrowly scoped RPCs; each function performs its own authorization checks and has execute privileges restricted to authenticated users.
- Supabase currently reports leaked-password protection disabled. Organizer sign-in uses magic links, but this setting can be enabled in Auth security settings as additional hardening.
