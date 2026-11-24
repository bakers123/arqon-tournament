# ARQON Esports Manager — live backend and data imports

## Runtime
- Telegram Mini App: `/manager/`
- Telegram launcher: inline Web App button in the existing `@arqon_esports_bot` main menu.
- Supabase Edge Function: `manager-api` (manual Telegram WebApp initData HMAC validation; JWT verification is disabled because the function validates Telegram's signed initData itself).
- Database: `manager_*` tables in the existing ARQON Supabase project.

## Security
- Mini App sends Telegram `WebApp.initData`; it never sends an owner/user id.
- Edge Function validates Telegram's HMAC and auth_date, then resolves the linked account through `telegram_accounts.chat_id`.
- An ARQON account must be linked to Telegram before creating a game club.
- Economy, contracts, training and match results are performed by server-side RPC functions. Client-supplied balances, rewards, scores and winners are ignored.
- The RPCs are revoked from anon/authenticated and granted only to service_role.
- All manager tables have RLS enabled. Pro catalogue data is read-only; private club data is owner-readable.

## Game database
- `manager_disciplines`: discipline roster sizes and role definitions.
- `manager_pro_teams`: real esports organizations, ranking source, rank and dated snapshot.
- `manager_pro_players`: real professional player handles and roster membership snapshots.
- `manager_clubs`, `manager_contracts`, `manager_wallet_ledger`: user organization and economy.
- `manager_training_sessions`, `manager_matches`: training and server-simulated matches.
- `manager_rank_snapshots`: requested ranking size, imported coverage, source and freshness status.

## Imported coverage (verified 2026-11-24)

| Discipline | Teams imported | Requested | Player records | Teams with verified rosters | Ranking snapshot |
|---|---:|---:|---:|---:|---|
| CS2 | 100 | 100 | 40 | 8 | HLTV, 2026-11-16 |
| Dota 2 | 40 | 50 | 20 | 4 | E-Rankings, 2026-11-01 |
| VALORANT | 48 | 50 | 40 | 8 | Riot Global Power Rankings, 2026-10-18 |
| League of Legends | 30 | 30 | 55 | 11 | Riot LoL Esports GPR, 2026-09-08 |
| **Total** | **218** | **230** | **155** | **31** | |

**Important data caveats**
- CS2 top 100 is an HLTV world-ranking snapshot dated Nov 16, 2026. The player roster table is verified only for eight organizations; other teams are imported as organizations without fabricated player names.
- Dota 2 ranks 1–40 are from the Nov 1, 2026 E-Rankings snapshot. The requested 41–50 are not imported yet. Its methodology counts tournament results over a trailing 12-month period and is not a prediction of current match strength. Only four team rosters are currently verified.
- VALORANT includes all 48 entries in the Riot Global Power Rankings snapshot after Champions on Oct 18, 2026. This is a dated official ranking snapshot, not a current Nov 24 ranking. The 50-team target is short by two. Only eight team rosters are currently verified.
- League of Legends includes the top 30 from Riot's GPR snapshot dated Sep 8, 2026. Eleven Worlds 2026 starting rosters are historical snapshots; offseason transfers after Worlds need a separate update.
- OVR/POT values in the game are ARQON balance attributes, not official player ratings. No placeholder player records were generated.

## Sources
- CS2 HLTV world ranking, Nov 16, 2026: https://www.hltv.org/ranking/teams/2026/november/16
- Dota 2 E-Rankings team world ranking, Nov 1, 2026: https://www.e-rankings.com/dota-2/ranking/teams/
- VALORANT Riot Global Power Rankings, Oct 18, 2026: https://liquipedia.net/valorant/Riot_Games/Global_Power_Rankings
- VALORANT ranking cross-check: https://esports.play-ascend.com/valorant/rankings
- League of Legends official Global Power Rankings: https://lolesports.com/en-GB/gpr/2026/current
- LoL Worlds 2026 roster cross-check: https://www.riftvanta.com/en/teams

## Next import milestone
Complete Dota ranks 41–50 and the remaining two VALORANT teams, then refresh VALORANT and LoL ranking snapshots. Verify and add player rosters team by team using dated sources; preserve historical roster snapshots rather than overwriting transfer history. After that, add scheduled refreshes and player/team detail pages.
