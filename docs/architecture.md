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

Each concrete record identity is caller-supplied (or callback-generated by source-game index). Newer position persistence shares work among multiple already-parsed games; optimizations must not change the correctness of canonical deduplication or occurrence sequences. Import benchmarks live in `apps/analysis/benchmarks/`: `pgn_batch_import.exs`, `pgn_import_query_profile.exs`, `pgn_import_phase_profile.exs`, `pgn_import_parallel_file.exs`, `pgn_import_persistence_concurrency.exs`, `pgn_multi_game_position_batch.exs`, `pgn_long_game_fixture.exs`, others. These often reset the selected DB; use only a disposable benchmark DB.

**Not yet implemented:** a complete provider-backed Lichess import/sync pipeline, a globally managed asynchronous production import queue, or a requirement that the LiveView demo search is wired to every production `GameSearch` capability. Inspect `Web.DemoData` and `RoomLive` separately from the domain pipeline; some UI controls still use demo data.

## 4. Chess features and advanced search

**Implemented `features` umbrella app** (integrated Oct 2026): `Features.extract/2` produces `Features.Result` with version (`Features.version/0`, currently `"0.1.0"`), canonical FEN and feature IDs/value map; `Features.compare/2` returns section-21 position-to-position similarity features. The source catalogue is `docs/POSITION_FEATURES.md`, currently organized into **21 sections**, and `Features.Catalogue` plus coverage tests enforce spec-to-implementation mapping.

The catalogue covers exact state, material, pawns, placement, mobility, center, space, squares, lines, attacks, king, tactical geometry, threats/motifs, strategic goals, tension, piece quality, initiative, position types, evaluation and similarity/structural relations. Examples in `Features.Catalogue.Similarity` include exact same position, side-to-move change, color reversal, mirroring, pawn-structure similarity, material patterns, pawn edit distance, strategic and tactical signatures, and comparable attack-plan indicators. **These are defined heuristics/indicators, not perfect semantic chess-plan inference.** Its symmetric pawn occupancy edit distance differs explicitly from the directional bounded edit-neighborhood search in `Analysis.PositionQuery`.

**Distinguish two layers:** `Analysis.PositionQuery` + `GameSearch` are PostgreSQL-native search facilities. Extracting/comparing rich `Features` vectors is implemented; a general indexed, planner-backed “find all Greek gifts / IQP plans / structural neighbors at 100M scale” engine using all catalogue fields is **planned**, not a verified current search capability. The long-term examples include exact/transposed positions, pawn structure shifts, piece substitutions, isolated-pawn pressure, Greek-gift themes and parameterized board squares. Query precision, semantics and physical indexes must be benchmarked before declaring such searches done.

## 5. Analyses and collaboration

### Mutable analysis — implemented

`Analysis.Analysis` is a rooted variation tree of `Analysis.Node` records; `Analysis.Analyses` provides create/load/play/edit/comment/NAG/variation services and PGN-derived analysis creation (`create_from_game_record/2`). Nodes refer to canonical position IDs, but the tree itself is **not** a canonical game. It can contain branches, comments/annotations and artificial edited positions, including positions outside normal legal gameplay. The aggregate is stored as a versioned binary record via `Analysis.AnalysisCodec` in `analyses` with optimistic revision checks (`Analysis.AnalysisStore`). Multiple analyses can reference the same game/position content without duplicating canonical data.

### Rooms — implemented

`Analysis.RoomStore` owns durable room codes and ordered `room_analyses` links. `Analysis.Rooms` is the API for creation, access, membership, chat and pruning. `Analysis.RoomServer` runs per-room GenServer state, registered/supervised with Horde, with ephemeral chat and presence/broadcasts (`Analysis.RoomEvents`, Phoenix PubSub/Presence in web). It can be recreated on demand from PostgreSQL after a worker/machine restart; visiting an unknown room must **not** create one. Room codes are reserved atomically; collision returns `{:error, :already_exists}`.

`Web.HomeLive` creates/joins rooms; `Web.RoomLive` offers chessboard editing, variations, PGN import, position tools, shared session, presence/chat, orientation and analysis switching. Direct room link is `/rooms/<CODE>`. A selected analysis/move may be deep-linked with `?a=<analysis-id>&p=<index,index,...>`; `p` is omitted at root. Navigation/board play keep it synchronized, normally with URL replace to avoid one browser history entry per move. Tests verify restart restoration and invalid path fallback. Optimistic client interaction was added to mitigate cross-region LiveView round trips.

### Room retention — implemented **current rule**

- `rooms.created_at` is required; `Analysis.RoomInventory.summary/1` / `old_empty_rooms/2` provide counts/candidates.
- `Analysis.RoomStore.prune_old_empty_rooms/2` uses a bounded `DELETE ... RETURNING` over old rooms with **no `room_analyses` membership**, using row locks/`SKIP LOCKED`; `Analysis.Rooms.prune_old_empty_rooms/3` also terminates their workers.
- **Production-only** `Analysis.RoomPruner` starts a minute after boot and runs every 24 hours: defaults **30 days**, **1,000 rooms maximum per run**; errors are logged, not fatal. The user verified manual cleanup and the scheduled worker in production.
- **Decision for future:** rooms should ultimately be ephemeral even when they contain analyses, **once those analyses can be discovered independently in personal libraries**. Do **not** describe that as today's pruning behavior. Decide library-claim UX, orphan retention/GC and ownership/authorization separately.

## 6. Identity, accounts, libraries, authentication and privacy

### Implemented at `51192f5`: storage and trusted domain APIs only

- `Analysis.Users.create/0`, `get/1`, `delete/1` manage internal UUIDs. `users` stores only `id`, `created_at`; deletion cascades linked accounts/library references **but not underlying analyses**. A UUID is **not** proof of session ownership.
- `Analysis.Accounts.link_verified/3`, `user_for_verified_identity/2`, `providers_for/1` link a **trusted, independently verified** provider subject to a User. Provider types are lowercase constrained strings (e.g. `lichess`, `github`), subject HMAC is 32 bytes. HMAC construction in source: `HMAC-SHA256(account_subject_hmac_key, provider <> <<0>> <> subject)`. Unique `(provider, subject_hmac)` prevents the same provider identity being assigned to two users. A user can link different providers; retrying the same link is idempotent. No raw provider `sub`, username, email, profile or OAuth token is saved.
- `Analysis.UserLibrary.save/2`, `list/1`, `remove/2` manage *references* to existing analyses. Save is idempotent; deletion of one reference does not delete the analysis or another user's link. FK constraints enforce valid user and analysis references.
- `config/dev.exs` and `config/test.exs` contain separate **non-production development/test HMAC keys**. The key is loaded at runtime by `Accounts` using `Application.fetch_env!(:analysis, :account_subject_hmac_key)` and requires ≥32 bytes. **Production HMAC key has not been configured in `config/runtime.exs` at baseline**; do so via a stable secret before calling account resolution/linking in a production OAuth flow. Losing/rotating the key naively breaks lookup of existing account links; design key rotation deliberately.
- Tests in `apps/analysis/test/analysis/user_identity_test.exs` cover UUID-only user shape, no raw subject in account table, distinct providers, linking conflicts, shared libraries, deletes and FK behavior. No authentication/authorization is enforced by these raw domain APIs; add it at trusted boundary.

### Implemented after the baseline: revocable session storage

`Analysis.UserSessions` provides trusted `create/1`, bearer-token resolution with `user_for_token/1`, and idempotent `revoke/1` / `revoke_all/1`. Migration `20261013170000_create_user_sessions.exs` adds `user_sessions`: a 32-byte SHA-256 token hash primary key, UUID user FK with cascading deletion, UTC creation/expiry timestamps, and a user index. PostgreSQL enforces hash size and expiry after creation. Credentials contain 256 random bits and use unpadded base64url; raw credentials never enter SQL. Session queries disable parameter logging.

Sessions expire after a fixed 24 hours using PostgreSQL statement time, without sliding renewal. Every resolution checks expiry and current database state; deleting a user removes all sessions. Issuance participates in the caller's transaction. A SHA-256 hash is sufficient for these high-entropy random credentials; this is separate from the stable keyed HMAC needed for guessable provider identities. There are no provider identifiers, OAuth tokens, IP addresses or user-agent fields in this table. Expired rows are rejected but not automatically pruned yet; cleanup must be added before enabling public login.

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

### Not implemented: web authentication/access control

- No OAuth2 authorization/callback endpoints, browser login/logout, browser identity plug, protected LiveView mount, account-grant storage, or Lichess library import/sync. Session storage, state/PKCE primitives, provider verification and atomic user resolution now exist as described above.
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

`Analysis.Application` starts DNSCluster plus `RoomEvents`, `AnalysisEvents`, Horde room registry/supervisor, and production `RoomPruner`. There is no distributed PostgreSQL owner process. Chat is transient across worker restarts. Current production is single-region; do not imply proven multi-region failover under present architecture.

**Local:** native PostgreSQL with `openchesslab_dev`/`openchesslab_test`, dev/test configs, migration tasks in `apps/database`. `config/test.exs` guards that `MIX_ENV=test` uses **exactly** `/openchesslab_test`; test helpers for analysis/web truncate PostgreSQL tables with `CASCADE` when suites start. Run in isolated/disposable databases, especially benchmark scripts. Platform-neutral commands and the user's Windows PowerShell/Arch Linux workflow are in `../AGENTS.md`.

**Known boundaries/backlog (planned, not shipped):** secure authentication/sessions and account linking, personal library LiveView, Lichess study/game access and import/sync, per-user/room authorization, later independent room-vs-analysis garbage collection, production asynchronous ingestion at high scale, full indexed plan/similarity search integration, robust production observability/load benchmarks, internationalization of chess SAN where appropriate. Treat each as a separately tested vertical slice.
