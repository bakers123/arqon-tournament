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
| CS2 | 100 | 100 | 122 | 25 | HLTV team pages, transfers and academy/prospect snapshots, Nov 2026 |
| Dota 2 | 40 | 50 | 163 | 15 | E-Rankings, 2026-11-01; Liquipedia roster history and TI 2026 shuffle tracker |
| VALORANT | 48 | 50 | 40 | 8 | Riot Global Power Rankings, 2026-10-18 |
| League of Legends | 30 | 30 | 55 | 11 | Riot LoL Esports GPR, 2026-09-08 |
| **Total** | **218** | **230** | **380** | **59** | |

**Important data caveats**
- CS2 top 100 is an HLTV world-ranking snapshot dated Nov 16, 2026. The player table now contains records for 25 organizations, including NAVI Junior, Spirit Academy, Inner Circle Academy and prospects from HLTV's November 2026 Prospects ranking. The free-agent pool includes eight players whose no-team departures were listed on HLTV's Nov 14–21 transfer feed. Two more recent HLTV bench moves are classified as benched, not free agents. One transfer-listed player uses an older Oct 6 snapshot and is explicitly dated. Some pro-team roster rows remain partial or need freshness checks.
- Dota 2 ranks 1–40 are from the Nov 1, 2026 E-Rankings snapshot. The requested 41–50 are not imported yet. Its methodology counts tournament results over a trailing 12-month period and is not a prediction of current match strength. Fifteen organization pools now contain player records. Eight Dota players are marked free agents from the post-TI 2026 roster-shuffle tracker (Aug 24 snapshot), including former Virtus.pro and LGD players. The tracker snapshot is older than the current date and is shown in the UI; statuses must be refreshed before treating them as live contract facts. Other historical players remain unverified unless a release is confirmed.
- VALORANT includes all 48 entries in the Riot Global Power Rankings snapshot after Champions on Oct 18, 2026. This is a dated official ranking snapshot, not a current Nov 24 ranking. The 50-team target is short by two. Only eight team rosters are currently verified.
- League of Legends includes the top 30 from Riot's GPR snapshot dated Sep 8, 2026. Eleven Worlds 2026 starting rosters are historical snapshots; offseason transfers after Worlds need a separate update.
- OVR/POT values in the game are ARQON balance attributes, not official player ratings. Academy/prospect OVR/POT values are gameplay estimates; names and team affiliations are sourced separately.

## Sources
- CS2 HLTV world ranking, Nov 16, 2026: https://www.hltv.org/ranking/teams/2026/november/16
- Dota 2 E-Rankings team world ranking, Nov 1, 2026: https://www.e-rankings.com/dota-2/ranking/teams/
- VALORANT Riot Global Power Rankings, Oct 18, 2026: https://liquipedia.net/valorant/Riot_Games/Global_Power_Rankings
- VALORANT ranking cross-check: https://esports.play-ascend.com/valorant/rankings
- League of Legends official Global Power Rankings: https://lolesports.com/en-GB/gpr/2026/current
- LoL Worlds 2026 roster cross-check: https://www.riftvanta.com/en/teams

## Roster import update (2026-11-24)\n- CS2: 74 player records across 15 teams. HLTV snapshots used: Nov 16 and Nov 9, 2026. The imported roster names include current lineups for FURIA, MOUZ, Spirit, Vitality, Falcons, Aurora, BetBoom, NAVI, PARIVISION, Legacy, 1win, Liquid and MIBR, plus FUT and The MongolZ from Nov 9.\n- Dota 2: 118 player records across ten teams. Liquipedia current and historical roster sections used for Team Liquid, Team Spirit, Aurora Gaming, Team Yandex, BetBoom Team, 1w Team, Tundra Esports, Natus Vincere and OG. Former/inactive players are marked in their role string as `Former • Position N`; they are not presented as current starting lineups.\n- The catalogue schema currently has no separate roster-status or join/leave-date fields. Historical status is preserved in the role label and source date, but a dedicated player-history table is a future schema improvement.\n\n## Next import milestone
Complete Dota ranks 41–50 and the remaining two VALORANT teams, then refresh VALORANT and LoL ranking snapshots. Verify and add player rosters team by team using dated sources; preserve historical roster snapshots rather than overwriting transfer history. After that, add scheduled refreshes and player/team detail pages.
