# OpenChessLab — current architecture

**Verified repository baseline:** `main` at `51192f5acceff601fe8b1bef225146eed72d0831`, 2026-10-13. **Status labels:** **Implemented** means present in that commit; **Decision** means agreed direction but not necessarily built; **Planned** means not yet implemented. Revalidate files before coding; Git is authoritative. Project-wide coding/deployment rules are in [`../AGENTS.md`](../AGENTS.md); why the architecture evolved is in [`development-history.md`](development-history.md).

## 1. Purpose and shape

OpenChessLab is a greenfield collaborative chess-analysis application. The data model deliberately separates a **position** (canonical board state), a **canonical played game** (starting position plus legal ordered moves), a **concrete game record** (one occurrence of that content with headers/metadata), an **analysis** (mutable branching tree that may include artificial positions), a **room** (shared session), and a **user library** (saved references to analyses). Future search must work at ≥100M positions and ≥10M games without constructing a new DBMS.

**Implemented runtime:** Elixir/Phoenix 1.8, Phoenix LiveView, Tailwind v4, PostgreSQL via `OpenChessLab.Repo` / Ecto SQL / Postgrex. Umbrella applications:

| App | Responsibility | Representative source |
|---|---|---|
| `chess` | Position, move, notation (FEN/SAN), legal moves, board/bitboard, canonical encoding, pawn structures | `apps/chess/lib/chess/` |
| `features` | 21-section chess feature catalogue and position-to-position comparisons | `apps/features/lib/features.ex`, `apps/features/lib/features/catalogue/`, `docs/POSITION_FEATURES.md` |
| `database` | Shared PostgreSQL Repo, migrations, release migrator | `apps/database/lib/open_chess_lab/repo.ex`, `apps/database/priv/repo/migrations/` |
| `analysis` | Position/game/record repositories, chess analyses, queries, PGN pipeline, rooms, identity links, libraries | `apps/analysis/lib/analysis/` |
| `web` | Phoenix controllers, LiveViews, board, collaboration UI, i18n | `apps/web/lib/web/` |

`mix.exs` declares the umbrella and release; `mix.lock`, `Dockerfile` and app `mix.exs` files are authoritative for dependency versions. This is a server-rendered LiveView app, **not** a React/SolidJS client. UI experiments considered other frameworks, but LiveView was retained. Default locale English; Dutch is configured (`config/config.exs`).

### Dependency and data flow

```text
Web.HomeLive / Web.RoomLive
     |           |                      (guest collaborative UX)
     |           +--> Analysis.Rooms --> RoomStore [PostgreSQL rooms + room_analyses]
     |           |                    \-> RoomServer / Horde / events / ephemeral chat
     |           +--> Analysis.Analyses --> AnalysisStore [PostgreSQL analyses]
     |           +--> Analysis.GameRecords / GameSearch
     |           |                    \-> GameStore, GameRecordStore, PositionStore
     |           +--> Analysis.PositionFeatures <--> Features catalogue
     |
     +--> (future authenticated library UI) --> Users / Accounts / UserLibrary
                                          \-> PostgreSQL users/accounts/user_analyses

Analysis.PgnImporter --> GameRecords <-- PgnBatchImporter
                             |
          PostgreSQL: positions, position_features, position_feature_vectors,
                      games, game_occurrences, game_records, analyses,
                      rooms, room_analyses, users, accounts, user_analyses
```

The flow sketch indicates logical ownership, not a promise of public HTTP endpoints. **Implemented router** (`apps/web/lib/web/router.ex`) exposes `/`, `/rooms/:code`, `/health`, `/ready`; at the baseline it has **no OAuth routes, user sessions or library page**. The room/library APIs are internal application functions, not authenticated external endpoints.

## 2. PostgreSQL is authoritative

All current persistent domain state is in PostgreSQL. Old `PositionDB`, `GameDB`, DETS/owner storage, custom posting index engines, and memory primary stores were removed. `OpenChessLab.Repo` provides connections; domain modules issue purpose-built parameterized SQL. The schema below reflects **the migrations at the baseline**, not just the envisioned conceptual schema.

### Core tables and real constraints

| Table | Identity and important columns | Constraints / access paths / notes |
|---|---|---|
| `positions` | Generated bigint `id`; 67-byte canonical `record`; `white_pawns`, `black_pawns` signed 64-bit bitboards | Unique `record`; pawn B-tree index on `(white_pawns, black_pawns, id)`; immutable canonical state |
| `position_features` | `position_id` bigint PK/FK → `positions.id`; `properties` array of `bytea` | GIN on `properties`; derived property keys for predicate search |
| `position_feature_vectors` | `position_id` bigint PK/FK; `version`, `fen`, JSONB `features`, timestamps | Versioned, richer per-position output of `Features` app; distinct from `position_features` |
| `games` | bigint `id`; 32-byte SHA-256 `fingerprint`; binary `content` | **Non-unique** index on `(fingerprint,id)`; exact content identity, not fingerprint uniqueness |
| `game_occurrences` | bigint `id`; `game_id` FK, `ply` bigint, `position_id` FK | Unique `(game_id,ply)`; lookup index `(position_id,id)`; includes starting position at ply 0 |
| `game_records` | bigint row `id`; unique textual `record_id`; `game_id` FK; `fullmove_number`; JSONB `metadata` | Metadata must be JSON object; index `(game_id,id)`; many concrete records may reuse one canonical game |
| `analyses` | bigint row `id`; unique textual `analysis_id`; bigint `revision`; binary `record` | Revision >0 and optimistic concurrency; `Analysis.AnalysisCodec` encodes the mutable aggregate |
| `rooms` | **text** `id` (room code) PK; `created_at` timestamptz NOT NULL | Unique reservation prevents code collisions; index on `created_at` |
| `room_analyses` | generated row `id`; `room_id` text FK → rooms; `analysis_id` text | Unique `(room_id,analysis_id)`; **no foreign key to `analyses` in the current room migration** |
| `users` | UUID PK (`gen_random_uuid()`); `created_at` | No name/email/password fields; internal identity only |
| `accounts` | bigint row `id`; UUID `user_id` FK; `provider` text; **32-byte** `subject_hmac`; `created_at` | Unique `(provider,subject_hmac)`; provider format check; index `user_id`; user deletion cascades |
| `user_analyses` | bigint row `id`; UUID `user_id` FK; `analysis_id` text FK → **unique** `analyses.analysis_id`; `created_at` | Unique `(user_id,analysis_id)`; index `analysis_id`; user/analysis deletion cascades only this reference |

**Exact migrations to inspect:** `20260930140300_create_positions.exs`, `20261001103000_create_games.exs`, `20261001140000_create_game_records.exs`, `20261002140000_create_analyses.exs`, `20261007090000_add_position_pawn_structure.exs`, `20261007094500_optimize_position_pawn_structure_index.exs`, `20261010100000_create_position_feature_vectors.exs`, `20261013110000_create_rooms.exs`, `20261013130000_add_room_created_at.exs`, `20261013143000_require_room_created_at.exs`, `20261013160000_create_users_accounts_and_user_analyses.exs`.

**Important identity distinctions:** `positions.id` and `games.id` are bigint database IDs. `game_records.record_id` and `analyses.analysis_id` are stable **textual** domain identities distinct from their generated SQL row IDs. `rooms.id` is a text collaboration code; `users.id` is UUID; `accounts.id` / `user_analyses.id` are generated row IDs. Never conflate these when adding joins, external URLs or foreign keys.

### Positions and query compilation — implemented

- `Chess.PositionCodec` defines the canonical 67-byte record. Deduplication uses byte-for-byte equality (`positions.record` unique), not a lossy similarity key. `Analysis.PositionStore` exposes real APIs including `append/1`, `append_many/1`, `get/1`, `find/1`, `page/2` (inspect actual specs before use).
- Position identity is about the canonical chess state, not display, notes, FEN halfmove clock, or how it was reached. The pawn bitboards are derived relational columns, NOT a second source of identity.
- `Analysis.PositionQuery` is the domain AST: boolean AND/OR/NOT, properties, `equivalent`, pawn-structure matches/transforms/symmetries, bounded edit neighborhoods (0–2 edits), single-push, capture-like, and missing-pawn neighborhoods. See the implemented constructors in `apps/analysis/lib/analysis/position_query.ex`.
- `Analysis.PositionQueryNormalizer`, `Analysis.PositionQuery.Postgres`, `Analysis.PositionQuery.PostgresPage` turn ASTs into SQL. PostgreSQL executes the predicates: GIN properties, B-tree pawn bitboards, and specialized ordered `UNION ALL` scans where benchmarked beneficial. The packed edit-neighborhood expression/key work is represented in compiler paths; inspect the actual SQL rather than presuming one specific index for all variants.
- `PositionStore.page/2` uses **keyset pagination**, bounded results and a high-water position ID captured with the first query, to avoid late inserts shifting an ongoing scan. Cursor is opaque; avoid offset paging and accidental full-result materialization.
- `PositionFeatures` connects canonical `Chess.Position`/position IDs/analysis nodes to versioned richer feature extraction in `Features` and persists `position_feature_vectors`. `position_features` (search property keys) and `position_feature_vectors` (catalogue extraction) fulfill different purposes.

### Games and concrete records — implemented

- `Analysis.GameContent` represents a **canonical game** as a starting position ID and ordered move list; its binary codec and SHA-256 fingerprint support deduplication. **Fingerprint is only a lookup bucket**, not proof of equality. `Analysis.GameStore` compares deterministic full content and uses a transaction-level PostgreSQL advisory lock for the fingerprint bucket to prevent concurrent duplicate exact games while permitting distinct colliding contents.
- `game_occurrences` map **each canonical game and ply** to a stored position, enabling transposition-aware game lookup independent of the move sequence. Occurrences belong to canonical content, not concrete PGN metadata.
- `Analysis.GameRecord` / `Analysis.GameRecordStore` distinguish each imported/scored game instance: textual `record_id`, canonical `game_id`, starting fullmove context, metadata JSONB (players/event/other PGN headers as supported by code). Multiple records may point at one game.
- `Analysis.GameRecords` owns orchestration and transaction boundaries; it includes `create_replayed/6` and **`create_replayed_many/1`**, used by the newer grouped importer. Within a group, shared positions can be persisted in a batch, followed by canonical games, occurrences, records in coordinated PostgreSQL transactions. Check the exact error/rollback semantics in code/tests.
- `Analysis.GameSearch` performs one joined PostgreSQL query **per page** over positions → game occurrences → concrete records; `Analysis.GameSearch.PostgresQuery` compiles SQL for predicate and metadata combinations. Keyset cursor captures high-water marks and tracks ordering `(position_id, occurrence_id, game_record SQL row id)`. `Analysis.GameRecordQuery` supplies metadata filters. This is not the old nested position-by-position N+1 flow.

## 3. PGN import pipeline — implemented, with different mode contracts

Entrypoints are `apps/analysis/lib/analysis/pgn_importer.ex` and `pgn_batch_importer.ex`. Do not collapse their error/transaction semantics:

| Entry point | Semantics |
|---|---|
| `Analysis.PgnImporter.parse/1`, `import_game/2`, `import_parsed/2` | Exactly **one** bounded game; rejects multi-game input. PGN SAN replay is validated, moves and headers parsed. Can use custom start FEN with correct `SetUp` tag and retained fullmove context; comments/NAGs/variations are **ignored for canonical played game content**. |
| `Analysis.PgnBatchImporter.parse/1`, `import_games/2` | Headered multi-game PGN; bounded full batch parse before persistence; parse failure causes no durable partial import. |
| `import_stream/2`, `import_stream/3`, `import_file/2` | Bounded streaming parsing; default parsed group size **10**. Each group commits atomically using replayed batch persistence; on group failure retries individual games in input order to preserve original successful-prefix + **one-based failure index** behavior. Explicit group size 1 uses original path. |
| `import_stream_parallel/3` or `/4`, `import_file_parallel/3` or `/4` | Explicit throughput mode; bounded concurrent windows, **one transaction per game**, failures collected with one-based source index, and processing continues after failures. **Not successful-prefix semantics**. |

**Room analysis import (2026-10-15, variations added same day):** `Analysis.PgnAnalysisImporter.import/3` wraps
single-game parsing with a full annotated-tree import. Brace/semicolon comments,
root comments, numeric NAGs and symbolic move suffixes are retained in the analysis;
`[%...]` machine commands are stripped from comments. Side variations graft as real
branches with their annotations intact: a variation following a move is an alternative
to that move, a sibling of the mainline child (nested arbitrarily deep), with positions
resolved through the legal-move rules and appended to the canonical position store.
The parser rejects unbalanced/unclosed variations, variations without a preceding move,
illegal variation moves, and invalid/excessive NAGs before persistence. Canonical
content and deduplication remain unchanged: the game record keeps only the mainline.
The game record and annotated aggregate
commit in one PostgreSQL transaction; failure rolls both back. RoomLive uses this path
for both pasted PGN and file upload, then adds the complete analysis through Rooms.
Custom SetUp/FEN starts, including black-to-move/fullmove context, were already supported
by PgnImporter and are covered through the room import flow as well.

**Multi-game and provider import (2026-10-16):** the import dialog accepts any mixture of
PGN text (several games at once) and Lichess game URLs, one per line, plus per-account
imports from the Lichess and Chess.com tabs. `Analysis.PgnBatchImporter.split_games/1` splits
multi-game PGN into per-game chunks (a header line following movetext starts a new game;
each part of a mixed box splits separately so headerless pasted games survive next to
headered fetched ones); every chunk goes through the annotated single-game importer, so
comments and variations are retained per game. `Web.GameImport` classifies the box line by
line and fetches providers with a descriptive User-Agent (both Lichess and the Chess.com
public API throttle or 404 generic clients): Lichess game URLs resolve in one batch
`POST /api/games/export/_ids`, Lichess accounts via `GET /api/games/user/{name}?max=N`, and
Chess.com accounts via the public monthly archive (`/pub/player/{name}/games/archives` →
latest month, newest N games). Chess.com game URLs cannot be resolved publicly and are
reported as skips. Partial imports report every failure as a listed skip (missing game ids,
invalid games, provider errors) and keep the dialog open; only a total failure is an error.

**Bulk corpus import (2026-10-17):** `Analysis.BulkImport` streams an external PGN dump —
built and smoke-tested against the lichess open database (CC0) monthly `*.pgn.zst` files —
into the canonical corpus. A `curl | zstd -dc` pipeline writes into a FIFO, so reads have
real backpressure and memory stays bounded for 29 GB sources (curl aborts stalled transfers
via `--speed-limit/--speed-time`); the downloader's exit status is written to a status file
so a truncated stream is reported honestly instead of looking complete. Games are filtered by
their header block (both players ≥ the rating floor, no bullet) **before** moves are parsed.
Kept games are persisted through the **grouped** importer by default
(`PgnBatchImporter.import_stream/3`, batches of ten: one transaction and one shared position
batch per group — the per-game parallel mode measurably collapsed to ~2 games/s through
pgbouncer on a small instance), with `mode: :parallel` still selectable. `:skip` resumes by
discarding input games during the header scan; `:record_id_offset` continues the record-id
sequence so a resumed run neither collides with nor duplicates already-imported games;
importer exceptions are captured into an honest error summary instead of crashing the
evaluation (worker machines run with restart disabled for the same reason). Entry points:
`mix run -e "Analysis.BulkImport.run(...)"` (development) and `/app/bin/openchesslab eval
"Analysis.BulkImport.run(...)"` (release machines; the function starts its own applications).
The runtime image ships `curl` and `zstd` for it. Known data caveat: pre-2014 lichess games
can carry from-square disambiguation (`Rc8c6` instead of `R8c6`) that the SAN parser
deliberately rejects; they surface as `:invalid_game` failures (≈12% of a 2013 month's kept
set, 0% of modern months). The book query has covering indexes:
`game_occurrences(position_id, move) INCLUDE (game_id)` and
`game_records(game_id, (metadata ->> 'result'), id)`; the production EXPLAIN of the starting
position's book went from 8.3 s to 0.5 s with them.

**Stored provider grants (2026-10-16):** a successful Lichess login or link now retains the
OAuth access token in `provider_grants` (one per user per provider), AES-256-GCM-encrypted
under the dedicated `PROVIDER_GRANT_KEY` (never the identity HMAC key; tokens are never
logged). The grant identifies the account at import time (`/api/account` → username), so a
linked user imports their recent public games without typing a username. Grants are deleted
on unlink, on account deletion (FK cascade), and when the provider rejects the token; a
missing key logs a warning but must never break login. Earlier the token was revoked
immediately after verification — that hygiene rule is deliberately replaced by encrypted
retention.

**Lichess library sync (2026-10-16, opt-in):** a linked Lichess account's owner can enable
"sync my games to my library" in the account modal (the account's own public games; the toggle
is off by default). `Web.LichessSync.Worker` (single-machine GenServer, 15-minute interval +
kick on enable) walks enabled grants via `Web.LichessSync`: resolve the account through the
token, page `GET /api/games/user/{name}?since=<cursor>&sort=dateAsc&pgnInJson=true` forward
(50 per page, max 3 pages per run), import each game through
`Analysis.LibraryImport.import_games/2` (canonical record + annotated analysis + library entry
titled "White – Black 1-0 (2026)"), advancing the `lastMoveAt` cursor per page. A 401 deletes
the grant and disables sync; unlinking removes the grant; deleting the account cascades.
Rate-limited pages leave the cursor in place for the next run. The worker is disabled in tests
(`config :web, :lichess_sync_worker, false`); `kick/1` tolerates an absent worker.

Each concrete record identity is caller-supplied (or callback-generated by source-game index). Newer position persistence shares work among multiple already-parsed games; optimizations must not change the correctness of canonical deduplication or occurrence sequences. Import benchmarks live in `apps/analysis/benchmarks/`: `pgn_batch_import.exs`, `pgn_import_query_profile.exs`, `pgn_import_phase_profile.exs`, `pgn_import_parallel_file.exs`, `pgn_import_persistence_concurrency.exs`, `pgn_multi_game_position_batch.exs`, `pgn_long_game_fixture.exs`, others. These often reset the selected DB; use only a disposable benchmark DB.

**Search UI (2026-10-15):** the room search modal queries the real corpus through `GameSearch.page/3` — one bounded keyset-paged PostgreSQL query per page, combining `PositionQuery.equivalent/1` (exact position from a FEN) with `GameRecordQuery` filters. `GameRecordQuery` gained `metadata_value_contains/2` (case-insensitive ILIKE substring on a metadata key, wildcards escaped) and `all/1`/`any/1` junctions for the player-name/colour/result combinations. Hits open as a fresh room analysis via `Analyses.create_from_game_record/2`. Position mode offers exact, same-pawn-structure, or any pawn-structure symmetry (color reversal and file reflection included); the edit-neighborhood predicates remain domain-only for now. The Lichess/Chess.com provider tabs in the import modal are still labelled demo fixtures.

**Not yet implemented:** a complete provider-backed Lichess import/sync pipeline or a globally managed asynchronous production import queue. Inspect `Web.DemoData` and `RoomLive` separately from the domain pipeline; the import provider mock still uses demo data.

## 4. Chess features and advanced search

**Implemented `features` umbrella app** (integrated Oct 2026): `Features.extract/2` produces `Features.Result` with version (`Features.version/0`, currently `"0.1.0"`), canonical FEN and feature IDs/value map; `Features.compare/2` returns section-21 position-to-position similarity features. The source catalogue is `docs/POSITION_FEATURES.md`, currently organized into **21 sections**, and `Features.Catalogue` plus coverage tests enforce spec-to-implementation mapping.

The catalogue covers exact state, material, pawns, placement, mobility, center, space, squares, lines, attacks, king, tactical geometry, threats/motifs, strategic goals, tension, piece quality, initiative, position types, evaluation and similarity/structural relations.

**Opening book (2026-10-15, folded into the reference panel 2026-10-17):** the moves column's
reference panel shows the corpus opening book with ECO classification. The `openings` table holds
the CC0 lichess-org/chess-openings dataset (~3,865 entries), seeded at migration time by replaying
each entry's PGN through the chess rules and keying by the canonical `PositionCodec` record
(collisions resolve to the longest line). `Analysis.OpeningBook` classifies exact positions,
classifies a line by its deepest named position (the recommended backward walk, transposition-safe),
and aggregates `game_occurrences.move` (filled at import; backfillable via
`GameStore.backfill_occurrence_moves/0`) into per-move counts with per-result record splits.
The panel shows the line's opening (name + ECO), the moves with counts, W/D/L bars and the opening
each leads to; clicking a move plays it. The book is local data only — its corpus fills from
imported games, not from room play.

**Endgame table (2026-10-16, folded into the reference panel 2026-10-17):** the reference panel
switches to exact 3–7 piece results from the public lichess tablebase API (`Web.Tablebase`,
`https://tablebase.lichess.ovh/standard`, one descriptive User-Agent request per lookup; the same
free service lichess.org itself uses). Positions with castling rights are skipped, API outcomes are
translated from the side-to-move perspective into colour terms per position (including the
50-move-rule cursed/blessed caveats). Every fetched result is cached permanently in
`position_tablebases` keyed by canonical `position_id` (`Analysis.PositionTablebases`), so the
external service sees one request per unique position ever, and a move can be played straight from
the list. Privacy note: the FENs of looked-up positions leave the server to lichess; results are
facts about positions, not user data. No local tablebase is shipped (7-piece data is terabytes).

**Room shell (2026-10-17):** the left sidebar was removed. A two-row **room bar** under the app
header carries the room code, presence (with follow buttons), latency, members, and the chat
button with unread badge (row one) plus the horizontal **analysis chip bar** with track/untrack,
new-analysis, import and setup actions (row two). Chat lives in a right-side drawer (bottom sheet
on mobile) with a closing backdrop; the mobile drawer-tab scheme (`RoomTabs` hook,
`data-mobile-panel`, the media-query block) was deleted, so mobile is a single scrolling column.
The board's height cap accounts for the bar (`min(100%, calc(100dvh - 20rem))`, shared with the
evaluation bar).

**Board overlays from the catalogue (2026-10-17, refined same day):** the LAYERS block was
replaced by pinning in the feature readout. Clicking a row shows its description and — when the
feature has squares — pins them on the board; the same click unpins. Pinned rows render in the
list itself (bold + accent label, `data-pinned` attribute) — a separate overlay chip row was
tried and removed (vertical clutter, scrollbars) because the five former layers are just
features, reachable in the list. `room_live` derives `feature_highlights` (`white`/`black`/
`neutral` square MapSets, `files`, and `white_heat`/`black_heat` square→level maps) from the raw
vector: per-side square lists or single squares, plain square lists, file letters, and per-side
square→count maps drawn as heat maps in three fixed opacity bands, normalised to the highest
count on the board (e.g. `mobility.per_piece`; other per-side maps like wing counts do not draw).
List-of-lists values (pawn chains) flatten one level. Aggregate features whose value holds no
squares (counts, pairs) draw through the catalogue's optional `board` hint on `Features.Feature`,
which names the piece type(s) to resolve from the current position for every side the value
affirms (`material.count.rook`, `material.bishop_pair`, `quality.bishop_pair`, …). Rows that can
draw carry a board-glyph cue (`data-drawable`). The board draws blue (white), red (black), amber
(neutral) tints, amber file bands and heat spans (`data-highlight`, `data-heat-level` attributes
for tests). Empty features stay
detail-only and never pin. `Chess.PositionProperties` is no longer used for board overlays (still
feeds the MATERIAL/SPACE strip tabs — pruning it is follow-up).

**Reference panel (2026-10-17):** the book and the endgame table share one contextual panel below
the move list (where the old inline comment box sat): opening name + ECO and corpus moves with
statistics while the position is in the corpus, the exact tablebase once seven or fewer pieces
remain. It loads asynchronously (`assign_async`, reset per position) so corpus aggregation — real
work on busy opening positions — never blocks a board move, and superseded loads are discarded by
key. Comment editing moved to a dialog opened from the moves-panel header button (with a marker dot
when the current node carries a comment and a delete action in the dialog).

Examples in `Features.Catalogue.Similarity` include exact same position, side-to-move change, color reversal, mirroring, pawn-structure similarity, material patterns, pawn edit distance, strategic and tactical signatures, and comparable attack-plan indicators. **These are defined heuristics/indicators, not perfect semantic chess-plan inference.** Its symmetric pawn occupancy edit distance differs explicitly from the directional bounded edit-neighborhood search in `Analysis.PositionQuery`.

**Distinguish two layers:** `Analysis.PositionQuery` + `GameSearch` are PostgreSQL-native search facilities. Extracting/comparing rich `Features` vectors is implemented; a general indexed, planner-backed “find all Greek gifts / IQP plans / structural neighbors at 100M scale” engine using all catalogue fields is **planned**, not a verified current search capability. The long-term examples include exact/transposed positions, pawn structure shifts, piece substitutions, isolated-pawn pressure, Greek-gift themes and parameterized board squares. Query precision, semantics and physical indexes must be benchmarked before declaring such searches done.

**Feature readout (2026-10-17):** the first product use of the catalogue is the room's engine-column **Features tab**: `Analysis.PositionFeatures.fetch_or_extract/1` extracts the full vector for the position on the board (once per canonical position — the vector is stored in `position_feature_vectors`, which is the groundwork for future similarity search), and the tab renders every feature grouped by spec section, in section order. Labels are humanized from the ids under their section heading (`tension.queenside_tension` → "Queenside tension"), booleans read Yes/No, collections show their count. Every feature has a curated one-line description in the EN catalog (`features.<id>`; NL falls back to EN); clicking a row opens a detail strip with the description, the raw id and the raw value. The engine tab strip became icon-only (aria-label + title carry the translated names) because four labelled tabs overflow the 210 px engine column — a labelled strip silently scrolled the `overflow-hidden` column and shifted its content left.

## 5. Analyses and collaboration

### Mutable analysis — implemented

`Analysis.Analysis` is a rooted variation tree of `Analysis.Node` records; `Analysis.Analyses` provides create/load/play/edit/comment/NAG/variation services and PGN-derived analysis creation (`create_from_game_record/2`). Nodes refer to canonical position IDs, but the tree itself is **not** a canonical game. It can contain branches, comments/annotations and artificial edited positions, including positions outside normal legal gameplay. The aggregate is stored as a versioned binary record via `Analysis.AnalysisCodec` in `analyses` with optimistic revision checks (`Analysis.AnalysisStore`). Multiple analyses can reference the same game/position content without duplicating canonical data.

### Rooms — implemented

`Analysis.RoomStore` owns durable room codes and ordered `room_analyses` links. `Analysis.Rooms` is the API for creation, access, membership, chat and pruning. `Analysis.RoomServer` runs per-room GenServer state, registered/supervised with Horde, with ephemeral chat and presence/broadcasts (`Analysis.RoomEvents`, Phoenix PubSub/Presence in web). It can be recreated on demand from PostgreSQL after a worker/machine restart; visiting an unknown room must **not** create one. Room codes are reserved atomically; collision returns `{:error, :already_exists}`.

`Web.HomeLive` creates/joins rooms; `Web.RoomLive` offers chessboard editing, variations, PGN import, position tools, shared session, presence/chat, orientation and analysis switching. Direct room link is `/rooms/<CODE>`. A selected analysis/move may be deep-linked with `?a=<analysis-id>&p=<index,index,...>`; `p` is omitted at root. Navigation/board play keep it synchronized, normally with URL replace to avoid one browser history entry per move. Tests verify restart restoration and invalid path fallback. Optimistic client interaction was added to mitigate cross-region LiveView round trips.

**Local engine analysis (2026-10-15):** the engine panel runs real Stockfish 19 (lite NNUE, single-threaded WASM, ~1.8 MB vendored under `priv/static/engine/` with its GPLv3 license) entirely in the browser, living in its own full-height column between board and move list (stacked before the moves on mobile). The `EngineAnalysis` hook owns the UCI worker lifecycle: it reads the current position FEN, depth and MultiPV from data attributes on the panel, (re)starts the search when they change, and pushes throttled (~4/s) info lines back as `engine-update` events. `RoomLive` converts UCI PVs to SAN via `Chess.Notation.UCI` (new: coordinate moves resolved against legal moves), normalizes scores to a white-relative value (UCI scores are side-to-move relative), and renders the stats, principal variations and the evaluation bar beside the board. Stale results (older FEN, switched-off engine) are dropped server-side; worker failures surface as an honest error state. Settings are session-only (depth 1–40, lines 1–10) and stay editable while the engine runs. Engine lines render as numbered, individually clickable moves (clicking move N plays the line up to N into the analysis via `Analyses.play/3`); hovering a move shows a small peek board of the resulting position, and the top line draws a green best-move arrow on the board. A session eval store keyed by canonical position id feeds a click-to-navigate evaluation graph and the **game review**: the hook walks every mainline position at fixed depth 12 (driven by data attributes, result per `bestmove`), and the server classifies by **win-probability drop** — lichess's published model (MIT-licensed scalachess formula, `Win% = 50 + 50 × (2/(1+e^(−0.00368208·cp)) − 1)`, mates saturate at ±1000cp), so big swings in already-decided games no longer misclassify. Marks: >30 points blunder, >20 mistake, >10 inaccuracy. Marks color the graph dots, render inline in the move list (with the swing as tooltip), and summarize with jump links to the critical moments. Finished evaluations persist per canonical position in `position_evals` (`Analysis.PositionEvals`), keyed by position id and engine identity (`stockfish-19-lite-single`), deepest-wins on upsert. Toggling the engine on at a covered position fills the panel instantly without starting the worker (the hook skips compute when the cached depth covers the request); completed searches persist on `bestmove`, and review results persist at the review depth. Positions are canonical, so evals are shared across rooms, games and sessions, and follow transpositions. A server-side or multi-threaded engine (COOP/COEP headers) remains future work.

**Implemented after `a6636d3`:** `Web.DisplayName.generate/0` supplies room participant labels such as `Brave Otter 42`, using curated English adjectives/animals and numbers 10–99. Presence, chat authors and annotation authors use the same server-assigned label during that LiveView lifetime. Names are generated afresh on mount and are not stored in the identity schema or derived from provider profiles. They need not be globally unique: the separate random participant ID identifies presence/chat participants. Room participation remains anonymous, including when a browser holds a login session.

### Private rooms, owners and invite links — 2026-10-14

Public rooms keep bearer-code semantics: knowing the code is entry. A private room
(`rooms.owner_user_id`, created through the signed-in "Private room" toggle) never treats
the code as access: `Web.RoomLive` renders only a gate card for non-members, without
subscribing to room events, joining presence, streaming chat or loading analyses — nothing
about the room leaks to guests or non-members. Owners become the first row of
`room_members` at creation; joining requires an invite link.

Invite links (user decision, 2026-10-14) are multi-use and revocable: `GET /rooms/:code/join/:token`
(`Web.RoomInviteController`) admits the signed-in opener as a member; guests are pointed at the
gate with a login hint and reopen the link after logging in. Only the SHA-256 hash of the token
is durable (`room_invites`, at most one active link per room); the raw token is shown to the owner
once, generating a new link rotates (revokes) the old one, and revocation stops new joins immediately
while existing members keep access. The invite row is locked `FOR UPDATE` before the membership
insert, so a concurrent revoke cannot admit anyone after cutoff. Owners manage links through the
owner-only Invite control (replacing Copy code in private rooms); forged invite events from
non-owners change nothing.

Member management lives in the owner's **Members** modal (2026-10-15): a durable member list
(`Rooms.members/1`) with required server-generated, non-PII display names stored per membership
(`Web.DisplayName`, `display_name NOT NULL`) plus join dates and an owner badge; private-room
presence uses the same stored member label, so the sidebar matches the list. Individual removal (`Rooms.remove_member/3`) is owner-only and never touches the owner's own
membership; removal publishes `membership_changed` over the room's event group, so every connected
view rechecks its own membership and a removed member is cut off immediately, redirected to the
gate with a removal notice. Guests and non-owners cannot forge list, invite or removal events.

Membership is user-based: private rooms require login for everyone including joiners. Account
deletion cascades ownership and memberships (`on_delete: :delete_all`). Room retention is
unchanged: private rooms are equally temporary, and pruning criteria still consider only
analysis membership.

### Room retention — implemented **current rule**

- `rooms.created_at` is required; `Analysis.RoomInventory.summary/1` / `old_empty_rooms/2` provide counts/candidates.
- `Analysis.RoomStore.prune_old_empty_rooms/2` uses a bounded `DELETE ... RETURNING` over old rooms with **no `room_analyses` membership**, using row locks/`SKIP LOCKED`; `Analysis.Rooms.prune_old_empty_rooms/3` also terminates their workers.
- **Production-only** `Analysis.RoomPruner` starts a minute after boot and runs every 24 hours: defaults **30 days**, **1,000 rooms maximum per run**; errors are logged, not fatal. The user verified manual cleanup and the scheduled worker in production.
- **Populated-room retention (2026-10-16, user's decision):** `rooms.last_active_at` is stamped on every visit, move/edit, comment and chat message. The pruner additionally deletes any room with no activity for **3 days**, together with its room analyses, in the same daily bounded pass (`Rooms.prune_inactive_rooms/3`, 1,000 max). Before deleting an analysis that a library entry tracks, the reference is materialized: the aggregate is cloned under a fresh id via the analysis codec and the entries repoint to it, so a pruned room never takes saved work. Canonical games, positions and occurrences are shared corpus content and are never pruned. Room links of pruned rooms simply start a fresh empty room on the same code when revisited.
- **Explicit removal (2026-10-17, user's decision):** the × on the active analysis chip removes that analysis from the room after a confirmation dialog. Removal only unlinks — the aggregate is deleted solely when no other room and no library entry references it (`RoomStore.cleanup_orphaned_analysis/1`, one conditional `DELETE` over `room_analyses` and `user_analyses`). `room_analyses.analysis_id` intentionally has no foreign key, so an add racing the delete can leave a membership row whose analysis is gone; the room UI already renders that as an unavailable analysis rather than failing.
- **Decision (2026-10-14, refined same day):** room work is shared; a library star tracks the room's own analysis as a **live reference** (room work is reflected in the library). Bringing a library entry into a room is an explicit choice: copy the underlying game only, copy the analysis, or live-share the analysis itself. Live-share first shows a confirmation warning (2026-10-15) explaining that the room works on the exact library-tracked analysis — every room edit lands in the owner's library — and offers the two copy routes as inline alternatives; the game-only alternative is hidden for entries without an underlying game. Private editing materializes a separate copy; there is no automatic synchronization. Closing the last browser tab must not delete work; work survives only while the room stays active (or is starred into a library).

## 6. Identity, accounts, libraries, authentication and privacy

### Implemented at `51192f5`: storage and trusted domain APIs only

- `Analysis.Users.create/0`, `get/1`, `delete/1` manage internal UUIDs. `users` stores only `id`, `created_at`; deletion cascades linked accounts/library references **but not underlying analyses**. A UUID is **not** proof of session ownership.
- `Analysis.Accounts.link_verified/3`, `user_for_verified_identity/2`, `providers_for/1` link a **trusted, independently verified** provider subject to a User. Provider types are lowercase constrained strings (e.g. `lichess`, `github`), subject HMAC is 32 bytes. HMAC construction in source: `HMAC-SHA256(account_subject_hmac_key, provider <> <<0>> <> subject)`. Unique `(provider, subject_hmac)` prevents the same provider identity being assigned to two users. A user can link different providers; retrying the same link is idempotent. No raw provider `sub`, username, email, profile or OAuth token is saved.
- `Analysis.UserLibrary.save/2`, `list/1`, `remove/2` manage *references* to existing analyses. Save is idempotent; deletion of one reference does not delete the analysis or another user's link. FK constraints enforce valid user and analysis references.
- `config/dev.exs` and `config/test.exs` contain separate **non-production development/test HMAC keys**. The key is loaded at runtime by `Accounts` using `Application.fetch_env!(:analysis, :account_subject_hmac_key)` and requires ≥32 bytes. **Production HMAC key has not been configured in `config/runtime.exs` at baseline**; do so via a stable secret before calling account resolution/linking in a production OAuth flow. Losing/rotating the key naively breaks lookup of existing account links; design key rotation deliberately.
- Tests in `apps/analysis/test/analysis/user_identity_test.exs` cover UUID-only user shape, no raw subject in account table, distinct providers, linking conflicts, shared libraries, deletes and FK behavior. No authentication/authorization is enforced by these raw domain APIs; add it at trusted boundary.

### Current Google/Lichess login and explicit linking — 2026-10-14

`Web.OAuthController` now owns both provider callbacks and CSRF-protected login/link
starts. `Web.OAuthAttempts` and `oauth_attempts` generalize the earlier Lichess-only
handshake (migration `20261014160000` renames the table). Encrypted attempt context
contains provider, login/link intent, nonce and initiating credential hash. Hash-only
PostgreSQL consumption remains atomic and independent of the account transaction.
Old pending handshakes must restart; existing account identities/sessions are unaffected.

`POST /auth/:provider/link` requires authentication. The callback checks the exact
initiating credential, then rechecks it after provider verification under `FOR UPDATE`
on its session row. Account linkage, replacement session issuance and old-session
revocation commit together. Existing provider ownership produces a conflict, never a
transfer or merge. Ordinary login resolves its own provider identity without linking.
Callbacks redirect to `/`; link conflicts surface as a flash on the home page.

Returning to a room (2026-10-14): the room shell's login, link and logout forms carry a
hidden `return_to` room path. Login and link store it in the encrypted, browser-bound
OAuth attempt context (`Web.ReturnTo.sanitize/1` accepts only internal single-segment
`/rooms/<code>` paths — anything else falls back to home, so a crafted value can never
become an open redirect); the callback redirects there on success and on link conflicts,
and callback parameters can never override the stored path. Logout sanitizes the same
form field. Home returns to home.

Linked accounts are a shell modal over the home and room LiveViews
(`Web.ShellPanels` + `Web.Layouts` templates), opened from the header account menu;
there are no `/library` and `/account` pages. **My library** has two surfaces with
distinct responsibilities (2026-10-14, user decision): the **Account menu opens a
library management modal** (`Web.ShellPanels.open_library/1`) with editor links,
renaming, removal and paging; the **import modal's My Library tab inside rooms**
(`Web.ShellPanels.load_library/2` + `handle_library_event/3`) lists the same
entries with only the import actions (game-only branch, analysis copy, live
share). Tab and modal events stay host-level, so `Web.UserAuth` revalidates the
browser credential before every handler, and every action re-checks the resolved
user: guests and revoked credentials only receive the login variant. Library entries
open ordinary private rooms (see below); there is no separate authenticated editor route. Escape closes any
modal, including while a field inside it has focus.

`Analysis.Accounts.unlink/2` (shell modal event `unlink-provider`, host-level and
revalidated per event) removes all identities of one provider after locking the
user's identity rows: concurrent unlinks can never strip the final provider, and
`:last_identity` is refused because there is no recovery. Sessions are untouched;
an unlinked user stays signed in and can relink the same identity later.

`POST /account/delete` (CSRF-protected, authenticated, `Web.AccountController`)
permanently deletes the signed-in account after a typed confirmation word
(`DELETE`, or the Dutch catalog word, case-insensitively). The modal's deletion
button stays disabled until the typed word matches (`account-delete-change`,
`Web.AccountController.confirmation_valid?/1`); the server-side check remains
authoritative for requests crafted outside the browser. It reuses
`Analysis.Users.delete/1`: linked identities, all sessions and personal library
links cascade in PostgreSQL, while underlying analyses and room content remain;
detached personal copies await the separate orphan-cleanup policy. The current
session is revoked, other tabs disconnect via the session topic, and a freed
provider identity can be linked to another account. There is no recovery, merge
or unlinking.

Google uses confidential-server OIDC with `openid`, PKCE and nonce, accepting identity
only from its direct TLS-verified token response. The response origin is authenticated
by HTTPS/client-secret exchange under Google's documented server-flow contract;
there is no browser-ID-token API or independent JWT signature verifier. Claims check
issuer, client audience/authorized party, expiry/issued-at and nonce. Only the HMAC of
`sub` is persisted. No emails, names or grants are stored; no offline access is requested.
Google tokens are discarded, while existing Lichess token revocation remains unchanged.
A linked Lichess identity is not a stored data-access grant. Import/sync remains future work.

See [Google setup and verification](google-auth.md) for configuration, deployment and
manual smoke tests. Earlier subsections below describe the incremental implementation
history; their Lichess-only names and pending-work statements are historical.

### Implemented after the baseline: revocable session storage

`Analysis.UserSessions` provides trusted `create/1`, bearer-token resolution with `user_for_token/1`, and idempotent `revoke/1` / `revoke_all/1`. Migration `20261013170000_create_user_sessions.exs` adds `user_sessions`: a 32-byte SHA-256 token hash primary key, UUID user FK with cascading deletion, UTC creation/expiry timestamps, and a user index. PostgreSQL enforces hash size and expiry after creation. Credentials contain 256 random bits and use unpadded base64url; raw credentials never enter SQL. Session queries disable parameter logging.

Sessions expire after a fixed 24 hours using PostgreSQL statement time, without sliding renewal. Every resolution checks expiry and current database state; deleting a user removes all sessions. Issuance participates in the caller's transaction. A SHA-256 hash is sufficient for these high-entropy random credentials; this is separate from the stable keyed HMAC needed for guessable provider identities. There are no provider identifiers, OAuth tokens, IP addresses or user-agent fields in this table. Expired rows are rejected immediately; periodic physical cleanup is described below.

This is a storage foundation only. `create/1` must only be called after independent authentication; accepting a browser-supplied user ID would be an authentication bypass. There is no browser login or protected route yet, and no active LiveView disconnection on revocation. Web integration must renew the session on login, use HttpOnly/Secure/SameSite cookies, enforce CSRF, validate tokens at protected mounts and events, and handle logout/disconnection. Anonymous rooms retain their existing behavior.

### Implemented after `2ba37c2`: single-use OAuth attempt primitives

`Web.LichessOAuthAttempts` owns the web protocol's pending login handshake, separate from `Analysis` user identities and sessions. `create/0` generates independent 256-bit state and PKCE verifier values and returns public S256 authorization parameters plus a private encrypted `browser_token`. Phoenix.Token encrypts the verifier using the existing endpoint secret key base and a dedicated purpose salt. No extra dependency or secret is introduced; changing that key invalidates outstanding attempts.

Migration `20261013180000_create_lichess_oauth_attempts.exs` stores only SHA-256 state/browser-token hashes and UTC creation/expiry times, with hash-size/expiry constraints and an expiry index. The five-minute lifetime is checked both by token decryption and PostgreSQL. `consume/2` matches both hashes in one `DELETE ... RETURNING`, checks expiry after acquiring the row, and returns the verifier to at most one caller. `cancel/2` consumes a denied attempt without returning the verifier. Wrong state or browser tokens cannot consume another attempt. Consumption is forbidden inside a surrounding transaction so later login failures cannot roll it back. Queries disable logging; no verifier, raw browser token, provider identity or access token is sent to PostgreSQL.

`prune_expired/0` deletes at most 1,000 expired rows with `SKIP LOCKED`; creation also invokes it. There is no idle timer: without new attempts or explicit pruning, expired hash records can remain stored but cannot be used.

These are protocol primitives, not installed cookies or HTTP routes. Future controllers must initiate via CSRF-protected POST, set the encrypted browser token in an HttpOnly/Secure/SameSite=Lax cookie, read it only from that cookie (never callback parameters), and clear it on callback. Consume before token exchange, including on denial; a failed exchange requires a fresh attempt. Client ID and redirect URI must come from trusted configuration and match the original request. This flow does not yet verify a Lichess identity, create a user session or support account linking.

### Implemented after `071d3e3`: provider exchange and identity verification

`Web.LichessOAuth.verify_callback/4` consumes a pending attempt before any HTTP request, exchanges its code/verifier with `POST https://lichess.org/api/token`, and retrieves the authenticated account using `GET https://lichess.org/api/account`. Its configuration argument must be supplied by trusted server code and contain the client ID and exact redirect URI used at authorization; there is no callback-parameter configuration or runtime OAuth enablement yet. The optional fifth argument is an HTTP test seam. The caller must obtain the browser token from its protected cookie; provider denial still uses the attempt module's `cancel/2`.

The client validates successful JSON responses, bearer token metadata and the account `id`. It returns only `%{provider: "lichess", subject: id}`; it never substitutes the display username. The returned subject is transient verified provider data and must be HMAC'd by `Analysis.Accounts` before persistence. The rest of the profile is discarded, including any names. No users, account links or sessions are created by this operation.

Once a syntactically usable access token is received, the client calls `DELETE https://lichess.org/api/token` even when profile/metadata validation fails. Successful verification requires a 204 revocation response. Errors contain only fixed atoms, not provider responses, codes, tokens or profile data. Network failures/process termination can still leave a Lichess grant alive; this implementation does not persist credentials to retry revocation and cannot guarantee remote revocation in those cases.

The existing OTP `:httpc` client is used; `:inets` and `:ssl` are declared runtime applications, with no new Hex dependency. Provider URLs are fixed HTTPS origins, certificate/hostname verification is enabled, redirects and Retry-After retries are disabled, connection/request timeouts are 5/10 seconds, and response headers/body are limited to 8/64 KiB. Non-loopback HTTP redirect URIs are rejected; local development callbacks may use HTTP. Tests use controlled responses and a loopback HTTP provider fixture, not a real Lichess account or a live OAuth grant. Browser integration and atomic internal-user resolution remain separate slices.

### Implemented after `a76b39e`: atomic verified-identity resolution

`Analysis.Accounts.resolve_verified/2` returns `{:ok, user_id}` for an independently verified provider/subject pair, creating a UUID User and HMAC-only Account when needed. This is a trusted domain operation, not verification of browser assertions. It accepts no target user ID and performs no automatic merging; explicit linking remains `link_verified/3` behind a future authenticated boundary.

Resolution runs in a PostgreSQL transaction and participates in an enclosing transaction, so session issuance can commit or roll back with first-login user/account creation. Existing accounts are looked up by provider/HMAC. When competing requests both find no account, the unique constraint arbitrates `INSERT ... ON CONFLICT DO UPDATE`: the conflict branch deliberately retains the existing owner and returns that owner's UUID. Any unused candidate User is removed within the same transaction. This also preserves ownership if explicit linking wins the race. Raw subjects never enter SQL. Concurrent deletion can invalidate any returned user later; session creation still checks that the user exists.

Tests force concurrent account inserts to overlap using a PostgreSQL table lock, verify no unused users remain, cover competing explicit linking, and roll back User/Account/session together. No schema change or new dependency is required. Production HMAC-key configuration and HTTP login integration are still pending; changing or losing that stable key would break account resolution.

### Implemented after `a0abd77`: authentication runtime configuration

`config/runtime.exs` reads the following server-controlled environment variables, in development and releases:

| Variable | Contract |
|---|---|
| `ACCOUNT_SUBJECT_HMAC_KEY` | Standard Base64 encoding of at least 32 secret bytes; decoded into `:analysis, :account_subject_hmac_key`. Generate independently of `SECRET_KEY_BASE`, keep stable and securely backed up, and use a separate value per environment. There is no generated fallback. |
| `LICHESS_CLIENT_ID` | Application client identifier; validated together with the exact redirect URI by `Web.LichessOAuth.validate_config/1`. |
| `LICHESS_REDIRECT_URI` | Absolute callback URL, without userinfo or fragment. HTTPS is mandatory in production; development permits HTTP only on loopback. |

Without both Lichess variables, `:web, :lichess_oauth` is `nil`; providing only one or an invalid value raises at startup. Complete configuration produces `%{client_id: ..., redirect_uri: ...}` for future trusted controllers. Production Lichess configuration additionally requires the explicit HMAC secret. A supplied but malformed/short HMAC secret fails even when OAuth is unconfigured. Missing overrides preserve the separate development/test keys from their environment config. Error messages name configuration variables without including their values. No client secret, provider scopes, endpoint override or token storage setting is added.

Generate the identity key once in a trusted terminal with `elixir -e 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(32)))'` (PowerShell and Bash). Store its output in the environment's secret manager, rather than in Git or logs; never regenerate it during a deploy. Runtime loading is implemented, but production secrets have not been provisioned by this slice and browser login routes remain pending. Tests evaluate the actual runtime file without starting a release or connecting to its configured database.

### Implemented after `cfa146f`: browser-bound login initiation

`POST /auth/lichess` runs through the existing browser pipeline with Plug CSRF protection. `Web.LichessAuthController.create/2` reads only trusted `:web, :lichess_oauth` configuration, creates an OAuth attempt and redirects to the fixed `https://lichess.org/oauth` authorization endpoint. The URL contains only the generated state/S256 challenge, `response_type=code`, configured client ID and configured callback URL. Request parameters cannot override them, add scopes or authenticate/link a supplied user ID. No User, Account or session is created.

The encrypted verifier-bearing browser token is delivered only in the host-only `_ocl_lichess_attempt` cookie: path `/auth/lichess`, 300-second lifetime, HttpOnly, SameSite=Lax and Secure. Secure is disabled only when both the current browser and configured callback use HTTP on the same loopback hostname. Responses use `Cache-Control: no-store` and `Referrer-Policy: no-referrer`. A repeated start overwrites the browser cookie with a fresh attempt; the previous attempt cannot be consumed using the replacement cookie and its database hashes expire normally. There is no GET initiation route. Unconfigured login responds 404 without an attempt or attempt cookie.

Controller tests enable the real CSRF check explicitly, obtain the signed session cookie/token from the home page and cover missing/wrong/cross-browser tokens, trusted parameters, cookie attributes, repeated starts and loopback development. This slice deliberately adds no login button: the callback, authenticated browser session, logout and expired-session cleanup still need implementation before public login can be enabled or production OAuth deployment recommended.

### Implemented after `43a0ca6`: verified callback and browser session issuance

`GET /auth/lichess/callback` reads the encrypted attempt token only from the browser cookie, clears that cookie and uses the configured client ID/redirect URI for provider verification. Provider denial consumes the bound attempt without exchange. Invalid, expired or replayed attempts cannot issue a session. Failures show a fixed message and retain an existing login; provider descriptions and client-supplied identities are never reflected or used for account resolution.

After verification and confirmed grant revocation, one PostgreSQL transaction resolves the verified identity, creates a fresh `UserSessions` credential and revokes the previous credential from the protected browser session. Failure rolls back User/Account/session changes but cannot restore the separately consumed OAuth attempt. Switching provider identities changes the login; it never links or merges users. Success clears prior browser session data, renews the session, deletes the prior CSRF token and redirects to `/`. The session contains the random `user_token`, not an asserted User ID or provider profile. Later access must resolve that token against PostgreSQL at its trusted boundary.

The Phoenix cookie now uses encryption and signing, explicit HttpOnly/SameSite=Lax and a 24-hour browser lifetime. Production compiles Secure=true independently of reverse-proxy request scheme; development/test support local HTTP. Existing guest locale cookies are intentionally invalidated by this greenfield change. PostgreSQL's 24-hour expiry remains authoritative even if later responses renew cookie retention. Phoenix parameter logs filter OAuth codes, state, verifier, browser/session/access tokens and provider descriptions. External proxy/access logs still require review before production enablement; these filters do not sanitize every possible external logging system.

Tests exercise actual router/cookie round trips with the provider client's trusted `:web, :lichess_oauth_request` HTTP test seam. Production runtime configuration supplies no replacement transport. They cover identity/session creation, repeat-login renewal, switching identities, denial, provider failures, missing/wrong/query-supplied cookies, replay/expiry, sanitized logging and an injected PostgreSQL session-insert failure. Logout, expired-session cleanup, authenticated LiveView access and the public login UI remain separate slices; production OAuth deployment is not yet recommended.

### Implemented after `118a47b`: browser logout

`POST /auth/logout` uses the browser pipeline's real CSRF protection. `Web.SessionController.delete/2` revokes only the credential read from the protected Phoenix session, before clearing the browser session and CSRF state. It deletes the session cookie and pending Lichess attempt cookie at their original paths and redirects to `/`, with no-store/no-referrer headers. Request parameters cannot choose a credential, User, all-session revocation or external redirect. The endpoint works for anonymous, malformed, expired or already-revoked sessions, independently of whether Lichess is configured. Other credentials for the same User remain valid.

Cookie deletion removes the pending attempt from the normal browser flow; its database hashes remain subject to the existing five-minute expiry/pruning. A retained encrypted session cookie can still decrypt after logout, but its credential no longer resolves in PostgreSQL. Future authenticated requests, LiveView mounts and events must use that resolution, rather than infer authentication from cookie contents. Active authenticated LiveView disconnection remains to be implemented with that boundary; current rooms are anonymous.

Tests obtain actual session cookies/CSRF tokens, verify missing/wrong/cross-browser CSRF rejection, GET rejection, session isolation, ignored request parameters, replay of an old encrypted cookie, browser/CSRF cleanup, anonymous/repeated logout and deletion of expired session rows. There is still no public login/logout UI, protected library route or scheduled expired-session cleanup.

### Implemented after `766aafc`: bounded expired-session cleanup

`Analysis.UserSessions.prune_expired/0` removes at most 1,000 expired session rows per statement, ordered by expiry and token hash. PostgreSQL's statement clock supplies the cutoff, and `FOR UPDATE SKIP LOCKED` permits concurrent passes while skipping locked rows for a later pass. Active credentials and Users are retained. Queries disable parameter logging. Migration `20261013190000_add_user_sessions_expiry_index.exs` adds the `(expires_at, token_hash)` B-tree access path for this query; this is a new cleanup facility, not a benchmarked hot-path optimization.

`Analysis.UserSessionPruner` is supervised only when `:analysis, :user_session_pruning_enabled` is true, enabled by `config/prod.exs`. It first runs one minute after boot and schedules one pass every hour, independently of login traffic. Each handled tick replaces the previous timer; failures log a fixed message without exception/credential details and schedule another pass. Multiple app instances can run this worker safely through PostgreSQL locks. Large backlogs require multiple passes; this is bounded cleanup, not a promise that all expired rows disappear immediately. Trusted operators can call `prune_expired/0` for additional passes.

Tests verify the 1,000-row bound, active-session preservation, deterministically locked rows, concurrent passes without double-counting, repeated worker ticks, production supervision, the migrated index and recovery after an actual database-query failure. Development/test do not start the periodic worker automatically. Public login UI and authenticated LiveView authorization/disconnection remain pending.

### Implemented after `e8422fa`: optional request/LiveView authentication

`Web.UserAuth` runs after session fetching in the browser pipeline and supplies `conn.assigns.current_user` from `UserSessions.user_for_token/1`. The public LiveView session uses its `on_mount(:default, ...)` hook to independently resolve the protected session credential for disconnected and connected mounts. Assertions of a User ID or credentials in request/event parameters are ignored. Missing, malformed, expired, revoked or deleted-user credentials result in `nil`; database failures abort processing rather than retain an unverified User.

Before each LiveView event, a hook re-resolves the original protected credential and updates `socket.assigns.current_user` before the view's handler. The credential stays in the hook's closure rather than public socket assigns. This prevents an event handler from relying on a stale mount-time identity after expiry/revocation. Public room events still work for guests. The session cookie may retain a revoked/expired credential so logout can remove its row; its presence alone never establishes authentication.

Tests cover HTTP session resolution, bogus/User-ID/query assertions, retained revoked cookies, connected mounts including revocation after the initial render, event-time expiry/revocation and actual public router mounts/guest rooms. This is optional authentication, not permission to expose private library data: private routes/mounts/events still require an explicit authenticated guard and per-user scope. Live patches/handle_params and active logout disconnection need that separate boundary; no private route or login UI is added here.

### Implemented after `4583a13`: active browser-session disconnection

Authenticated HTTP requests and successful login callbacks set Phoenix's protected `live_socket_id` to a session-specific SHA-256 credential digest topic, never the bearer token or a user-wide topic. Logout revokes the credential before broadcasting Phoenix's `disconnect` event. A successful replacement login broadcasts for the previous credential only after the account/session transaction commits. Failed provider verification or database rollback leaves existing connections alone. The topic is derived from the protected credential; request parameters cannot choose another connection to disconnect.

Phoenix closes all transports subscribed to that session, including other tabs; other sessions for the same User remain connected. Reconnection independently resolves PostgreSQL state. Revocation between HTTP rendering and socket subscription is still covered by connected-mount/event revalidation. Broadcasts are transient notifications, not durable authorization. Direct domain revocation, user deletion and natural expiry still rely on mount/event checks; no idle expiry timer or database notification mechanism is introduced. Tests exercise real Phoenix transport connect/init/disconnect callbacks, multiple connections, isolation, replacement login and failed-login rollback.

### Implemented after `d958542`: login/logout interface

The shared home/room header offers a native POST form to log in with Lichess only when server-side OAuth configuration is present. A resolved `current_user` instead receives a logout form, even if provider login is disabled. Phoenix generates CSRF fields for both forms; these are ordinary browser requests to the existing controllers, not LiveView authentication events. English is the default, Dutch labels are available, and compact labels/header wrapping accommodate smaller screens. The UI exposes no internal User ID, provider profile or session credential. Existing event-time revalidation updates the controls when a credential is revoked.

The shared layout renders error flashes as an accessible alert; callback failures use a fixed translated message without provider details. Tests cover both routes/languages, configuration gating, revocation, privacy and actual POSTs with rendered CSRF fields. Login/logout still redirect to home; rooms remain guest-accessible. No personal library UI or private authorization policy is implied. Production enablement still requires stable HMAC/provider configuration and an external access-log review; deployment remains manual.

### Browser preferences before authentication redirects

`Web.BrowserPreferences` reads presentation-only `_ocl_theme` (`system`/`light`/`dark`) and `_ocl_locale` (`en`/`nl`) cookies before locale negotiation. Values are allowlisted; they never establish identity. The selected theme is copied into the protected LiveView session for both home and room mounts, and the document root carries it before CSS renders. Theme variables apply at the document root so the body background follows the same choice. Explicit locale query parameters retain precedence over the saved preference.

The browser mirrors its existing local theme/language preferences into host-only, one-year, SameSite=Lax cookies (Secure over HTTPS), both when restoring them and when the user changes them. These cookies intentionally permit JavaScript updates and contain no credentials. Login/session renewal and logout/session deletion leave them intact, so the next HTTP response already uses the selected theme and language. Existing localStorage-only preferences acquire their cookie mirror when the updated client first mounts; that initial visit still needs client restoration. If cookies are blocked, local restoration remains available but initial server rendering cannot know the saved preference. Tests check initial HTML and connected mounts on both public routes, successful callback/logout with session clearing, invalid values, cookie attributes and blocked storage.

### Authenticated personal library list

`/library` is a separate authenticated LiveView session. Its HTTP pipeline requires a resolved User and sends `Cache-Control: no-store`; `Web.UserAuth` in `:required` mode independently resolves the credential at both mounts and before each event and `handle_params` callback. Missing, expired, revoked or deleted-user credentials halt processing and redirect home with a translated login prompt. Public home/room routes retain optional authentication. Authentication checks are per request/event, not a claim of serializability with concurrent revocation, and idle expiry still has no timer.

`Web.LibraryLive` lists, renames and removes references exclusively using the server-resolved User ID. It ignores client-provided owner and cursor values; paging uses its current server-side cursor. `Analysis.UserLibrary.page/2` reads at most 50 references plus one lookahead row in analysis-ID order, with keyset continuation using the existing unique `(user_id, analysis_id)` index. It reads reference IDs, saved dates and personal titles only, without loading analysis trees or issuing per-entry queries. The older trusted `list/1` API remains available for domain use.

Migration `20261014150000_add_user_analysis_titles.exs` adds a nullable `user_analyses.title`,
constrained to 1–120 Unicode code points when present. `UserLibrary.rename/3` normalizes
whitespace and clears blank titles to NULL, updating only the authenticated caller's reference.
`title/2` is likewise user-scoped. These trusted APIs require authentication at the web boundary.
Titles are personal library labels, independent of the analysis aggregate/revision, room content
and another user's references; simultaneous title saves use the latest committed write.
The list opens an inline rename form only for a server-selected entry on the current page;
submitted owner/analysis IDs cannot redirect the save. HTML output escapes titles. Untitled items
use an English/Dutch fallback, and the library displays the saved label.
Existing references need no tree reads or backfill; users can label them directly.

The home/room header links signed-in users to the library. The page has English/Dutch text, keeps the document theme/locale, and offers removal of a saved reference without deleting the analysis or another user's reference. This first interface shows analysis identifiers and saved dates; opening a saved analysis, richer labels and private analysis editing/sharing are subsequent slices. Tests cover HTTP and connected-mount denial, event/navigation revocation, user deletion, forged owner parameters, paging and shared-analysis preservation.

The shared home/room header groups authentication and the linked-accounts control under **Account**; the personal library is reached from the room workspace's import modal. A single theme button cycles system → light → dark → system using the existing preference-persistence event; its accessible label and tooltip identify the current and next setting. Status colours (`--error`, `--success`, `--warning`) are theme-adaptive like `--focus`/`--highlight`, so status text and UI meet WCAG AA contrast in both themes (light: `#a84848`/`#387038`/`#8f6120`; dark: `#e57b7b`/`#7bc97b`/`#d4a14a`). **Help** (shortcuts/tour) and piece-set controls are available only in room workspaces, where they have relevant content; the home entry page has language, theme and Account controls. A single theme button cycles system → light → dark → system using the existing preference-persistence event; its accessible label and tooltip identify the current and next setting. Native disclosure menus support keyboard use, Escape and outside-click dismissal. Room controls are available on mobile too. Home Create/Join cards align their primary action row and size independently, so a Join error does not move the Create button or caption.

### Library stars and live references — 2026-10-14

Signed-in room participants see a **star** on every analysis entry. Clicking it tracks the
room's own analysis in their library as a **live reference** — no copy is made, so work in
the room is reflected in the library while the analysis exists; clicking again un-tracks.
`Web.RoomLive` fills the star optimistically, reverts and reports on failure, and uses only
the event-time credential-resolved User with a server-side room and analysis id; supplied
owner, room and analysis parameters are ignored. Guests and revoked/expired credentials
never see the star and cannot track. `UserLibrary.tracked/2` re-renders the starred state
whenever the room's analysis set changes.

`Analysis.UserLibrary.track_from_room/3` is a trusted domain API, not an authentication
boundary. In one PostgreSQL transaction it locks the existing User against deletion,
verifies durable room membership while holding shared row locks on the membership and
analysis, and inserts the library reference idempotently. Nothing is copied, added to the
room or broadcast; repeated and concurrent tracks converge on one reference per owner.
Un-tracking (`remove/2`) removes only the reference, never the analysis or room content.
The earlier snapshot-at-save behavior (`copy_from_room/3`) was removed with it: branching
— copying a game or analysis into a room, live-sharing, and materializing private copies —
is explicit and separate, keeping other users' references tracking the original.

The existing `user_analyses` schema stores the reference; no ownership column, migration
or sharing endpoint is introduced. The trusted `save/2` primitive still inserts references
internally and is not exposed as a browser save operation. Library removal still removes
the association only, so orphan cleanup/user deletion semantics need a separate policy.
Opening an entry uses the ordinary private-room editor described below. Room
expiry/cleanup behavior is unchanged; analysis rows currently outlive rooms.

### Branching library entries into rooms — 2026-10-14

The import modal's **My Library** tab lists the user's entries with `UserLibrary.page/2`
(including per-entry underlying-game availability). Each entry offers the three explicit
branch actions, all verified against the resolved user's library and added through the
room server (`Rooms.add_analysis/3` broadcasts to every member):

- **Game only** (`branch_game/2`): `Analyses.create_from_game_record/2` builds a fresh
  analysis from the entry's underlying game — the canonical main line without the entry's
  variations, comments or NAGs, so private analysis stays private. Entries without a game
  do not offer the action (`:game_not_available`).
- **Analysis copy** (`branch_analysis/2`): a snapshot copy with a fresh id preserving the
  whole aggregate; later room work never flows back into the entry.
- **Share live** (`authorize_share/2` + the room add): the entry's exact analysis joins the
  room under its own identity — work in the room appears in the library entry (the star),
  which is the across-days collaboration mode.

Adding closes the import modal, refreshes the room, selects the analysis and reports the
result. Guests and revoked credentials cannot branch; forged owner, entry or room
parameters are ignored. The paste-import demo fixtures are untouched; the earlier demo
library-tab fixtures were replaced by the real library.

### Personal analyses in ordinary private rooms — 2026-10-15

The library modal's `library-open` event calls `UserLibrary.open_room/4`, then
redirects to `/rooms/<code>?a=<analysis-id>`. The same `Web.RoomLive` handles public,
private and library work, including position tools, engine, review and collaboration.
`Web.PersonalAnalysisLive`, `/library/:id`, and the separate private read/edit APIs
have been removed. Authentication and membership use the existing private-room gate.

The transaction locks the analysis and the requesting user's library reference.
An existing private room owned by this user containing the entry is reused, including
rooms with invited members. Otherwise, an entry linked to a room or another user's
library is copied and the user's reference repointed, preserving its personal title.
An unshared entry keeps its analysis id. Private room creation, owner membership and
analysis linkage commit atomically with the copy/reference update; a code collision
rolls everything back. Other users' references and source rooms remain unchanged.
The web boundary supplies the authenticated user, random room code and generated
member label. The room worker starts only after commit, on normal RoomLive mount.
Removing a library reference does not revoke room membership or delete the room.


### Remaining integration

- No account-grant storage or Lichess library import/sync. Private editing is scoped as above; room permissions remain separate work.
- `user_sessions` now exists as described above; `account_grants` remains a proposal. Avoid assuming Better Auth (a different ecosystem) is installed; **User → multiple Accounts is the adopted *model***, not a library dependency.
- Users should not see unrelated users' analyses by default once ownership/scoping is introduced. Existing room collaboration remains link-based, guest-capable; future policy must define who can view, edit, claim or share analyses, and how anonymous work joins authenticated libraries. No automatic linkage based on matching email addresses.

### Decisions for future Lichess integration

1. Use **Lichess OAuth 2.0 Authorization Code with PKCE S256**, verifying state and redirect URI and retrieving the provider identity through a trusted provider endpoint before calling `Accounts.link_verified/3` or `user_for_verified_identity/2`.
2. Create a **secure server-side session** bound to the internal User; only store opaque, suitably hashed session credentials with expiration and revocation if persisted. Do not expose internal `Users.create/0` or Accounts linkage directly to untrusted clients.
3. Ask for minimal provider scopes. **Authentication** and **access to private studies/parties** are distinct consent steps. Public Lichess data might be fetched without a private grant; private user content requires appropriate granted scopes. Consult the **current** Lichess API/scopes documentation before coding (the provider may evolve).
4. If long-lived access is necessary, introduce a **separately encrypted** grant/token storage design (key management, revocation, expiry, scope tracking). Do not persist raw tokens in `accounts`, logs or PGN metadata. OAuth grants are not part of the current schema.
5. Preserve the principle **one User, zero or more Accounts**. Account linking must happen only when the current User is securely authenticated and completes a fresh verified provider flow. Never silently merge identities on email/name. Decide recovery and what happens when accounts are unlinked or users deleted.
6. Imported studies and games are third-party data. Map a Lichess study's potentially branching/comments content to **analysis trees**, not merely canonical game moves; played games map to canonical game + concrete game record. Keep provider object identity, sync semantics, conflict handling and permissions explicit when implementing.

**Privacy terminology:** This design avoids direct identification data **in identity storage**, not necessarily all personal data application-wide. HMAC'd provider identifiers are generally pseudonymous rather than legally anonymous; PGN metadata may contain player names, free-text analysis/chat content can contain personal details, OAuth temporarily exposes provider data, and server/IP/access logs may contain identifiers. Minimize what is collected, retained, logged and exported; document concrete policy when OAuth/import shipping is contemplated. Do not make absolute “no PII anywhere” compliance claims.

## 7. Runtime, deployment, tests and current boundaries

**Implemented deployment:** Fly.io app `openchesslab`, single `app` machine in **Amsterdam (`ams`)**, Fly Managed PostgreSQL, canonical `openchesslab.com` with www redirect. The release command in `fly.toml` invokes `/app/bin/openchesslab eval "OpenChessLab.Database.Release.migrate()"`; `/health` and `/ready` are passing health-check routes reported by the user. `config/runtime.exs` configures the direct Fly Postgres endpoint (`@pgbouncer.` → `@direct.`) and IPv6 sockets when `ECTO_IPV6=true`; this was deliberate to address earlier DNS issues. Inspect runtime/infra config before changes. **Manual** `flyctl deploy --remote-only -a openchesslab` is the chosen production flow; do not re-enable auto-deploy.

The app Machine was explicitly resized to **512 MB, one shared CPU** on 2026-10-14;
`fly.toml` retains this size for subsequent deployments. Post-resize health/readiness passed;
approximately 227 MiB was available immediately after restart, without swap. Load peaks still need observation.

`Analysis.Application` starts DNSCluster plus `RoomEvents`, `AnalysisEvents`, Horde room registry/supervisor, and production `RoomPruner`. There is no distributed PostgreSQL owner process. Chat is transient across worker restarts. Current production is single-region; do not imply proven multi-region failover under present architecture.

**Local:** native PostgreSQL with `openchesslab_dev`/`openchesslab_test`, dev/test configs, migration tasks in `apps/database`. `config/test.exs` guards that `MIX_ENV=test` uses **exactly** `/openchesslab_test`; test helpers for analysis/web truncate PostgreSQL tables with `CASCADE` when suites start. Run in isolated/disposable databases, especially benchmark scripts. Platform-neutral commands and the user's Windows PowerShell/Arch Linux workflow are in `../AGENTS.md`.

**Known boundaries/backlog (planned, not shipped):** secure authentication/sessions and account linking, personal library LiveView, Lichess study/game access and import/sync, per-user/room authorization, later independent room-vs-analysis garbage collection, production asynchronous ingestion at high scale, full indexed plan/similarity search integration, robust production observability/load benchmarks, internationalization of chess SAN where appropriate. Treat each as a separately tested vertical slice.
