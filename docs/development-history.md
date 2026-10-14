# OpenChessLab — development history, benchmarks and decisions

**Handoff baseline:** `main` at `51192f5acceff601fe8b1bef225146eed72d0831`, 2026-10-13. This is a history and rationale document, **not** an authority for current function signatures. Check Git/SQL/tests before implementing. Engineering rules are in [`../AGENTS.md`](../AGENTS.md); the as-built model and explicit *Implemented / Decision / Planned* boundaries are in [`architecture.md`](architecture.md).

## 1. Guiding decisions and architectural pivots

| When / phase | Decision and reason | Current status |
|---|---|---|
| Sept 2026, foundation | Create an Elixir umbrella with chess rules, immutable shared positions, mutable analysis trees, collaborative rooms; prefer working vertical slices over abstract repository behaviours without real implementations. | **Implemented**, considerably evolved. |
| Sept 2026, modelling | Split **canonical chess game content** from **concrete game records**. SHA-256 fingerprint narrows lookup, but *complete encoded content* decides equality. Introduce per-ply position occurrences for transpositions and search. Keep analysis trees separate, allowing illegal/what-if edits and variations. | **Implemented**, central invariant. |
| Sept 2026, early persistence | Initially experimented with custom PositionDB/GameDB segments, append markers, recovery, posting/occurrence indexes, memory/DETS and Horde ownership. Two-region Fly owner/replica in AMS/ORD tested latency, persistence and recovery. | **Historical, removed**. Do not reconstruct it. |
| 2026-09-29 to 2026-10-02 | User explicitly preferred the principles of a **real DBMS** over recreating one. Migrated storage and search to **PostgreSQL**; removed PositionDB/GameDB disk engines, DETS, store-owner routing and redundant facades. PositionStore, GameStore, GameRecordStore and AnalysisStore became PostgreSQL-backed. | **Implemented**. |
| 2026-10-01/02 | Nested cross-store position→game→record lookup created hundreds of queries per page. Moved full search to a **single PostgreSQL join per page**, keyset cursor plus first-page high-water bounds. | **Implemented; benchmarked**. |
| 2026-10-02 | Fly Managed PostgreSQL and one AMS app process replaced owner/replica storage. Direct MPG endpoint, IPv6 sockets and release-time migrations stabilized the deployment. Auto-deploy intentionally disabled; **manual** Fly deployment is the desired workflow. | **Implemented**. |
| 2026-10-05 to 2026-10-12 | Introduced bounded and file-backed PGN parsing/import, replay sharing, one transaction per game, grouped atomic persistence, batched positions, streaming and parallel modes. Iteratively profiled SQL vs SAN/CPU vs peak memory. | **Implemented**, mode semantics differ. |
| 2026-10-07 | Search expanded from exact/properties to pawn structures, transformed/reversed/reflected structures, symmetries, local edits (including distance 2), pushed/capture-like/missing-pawn neighborhoods. Benchmarked planner and B-tree/GIN behavior; added ordered `UNION ALL` paths where advantageous. | **Implemented for listed query ASTs**. |
| 2026-10-08 to 2026-10-13 | Added `features` umbrella app using `docs/POSITION_FEATURES.md`: 21-section chess-feature catalogue, attack/bitboard caches, structural and tactical similarity, versioned persistence via `Analysis.PositionFeatures`. | **Implemented feature extraction/comparison**; global indexed feature-vector search still planned. |
| 2026-10-13 | Persist rooms and ordered memberships in PostgreSQL; room workers remain ephemeral. Restore analyses after worker restart; collision-safe codes; selected analysis position in deep-link URL, synchronized as moves/navigation change. | **Implemented; LiveView regression tests**. |
| 2026-10-13 | Introduced read-only inventory, required room creation timestamp and bounded removal of old empty rooms. Production `RoomPruner` runs after startup/daily (30 days, ≤1,000 per run); verified deployed and old empty rooms removed. | **Implemented current empty-room rule**. |
| 2026-10-13, product decision | Room is temporary; **analysis is durable independent of the room**. Eventually a room may expire regardless of attached analyses, provided personal libraries/recovery/permissions are defined. | **Refined by the explicit-copy decision on 2026-10-14 below; not current pruning behavior**. |
| 2026-10-14, personal work | Save an independent personal copy from shared room work; future explicit sharing should copy back into a room. No automatic synchronization. Eventually room deletion removes room analyses, while personal copies survive. | **Room-to-library copies implemented; private editor, copy-back sharing and populated-room retention remain planned.** |
| 2026-10-13, identity | Rejected email-based local `users` model before integration. Adopted **PII-minimizing** `User → 0..N Accounts`, provider + HMAC of subject, library references, no local password/email/name. Lichess first external provider; OAuth2/PKCE and private study/game scopes later. | **Identity/library schema and trusted APIs implemented in `51192f5`; OAuth/sessions/UI planned**. |

**Product principles:** No established user base; no backward-compatibility constraint. Default English, Dutch available; later SAN localization considered. User privacy, ownership and effective retrieval matter more than keeping a room code forever. A user's analyses should not be globally visible by default after auth/access controls are introduced. A room's unguessable code currently functions as its collaboration invitation; it is **not an authenticated ownership model**.

## 2. Verified milestone commits

The following commit subjects and hashes were checked against the repository's GitHub history during handoff. Dates are commit dates, **not claims that all functionality was deployed at that moment**. These are useful starting points for `git show`, `git log` and `git blame`, not replacements for current code.

### Pre-PostgreSQL and storage cutover

| Commit | Change |
|---|---|
| `b703de618` (2026-09-25) | Add Fly owner and replica process groups (**historical**, subsequently removed) |
| `a2e64d69c` (2026-09-25) | Persist clustered game store with DETS (**removed**) |
| `d107611ef` (2026-09-29) | Integrate LiveView UI with analysis backend |
| `2aabc400c` (2026-10-02) | Collapse game search into PostgreSQL-native paging |
| `c6d8ad0b4` (2026-10-02) | Push game search keyset into occurrence index |
| `9621eedd6` (2026-10-02) | Persist analyses in PostgreSQL |
| `f8cb07dac` (2026-10-02) | Configure PostgreSQL for Fly private networking |

### PGN and chess-search expansion

| Commit | Change |
|---|---|
| `68daa9ddc` (2026-10-05) | Add durable PGN game import service |
| `1634dc32f` (2026-10-05) | Support custom FEN starts in PGN imports |
| `e9cd0aabd` (2026-10-05) | Add streaming PGN batch imports |
| `57c2bb02a` (2026-10-05) | Add file-backed PGN batch imports |
| `b63175973` (2026-10-05) | Batch replay position persistence |
| `35ecf4120` (2026-10-05) | Insert canonical game and occurrences together |
| `be147b082` (2026-10-05) | Revert "Insert position features with positions" (optimization was not retained) |
| `f2de686f3` (2026-10-07) | Add bounded parallel PGN import |
| `0fc0143fd` (2026-10-07) | Search positions by exact pawn structure |
| `c9772da89` (2026-10-07) | Optimize pawn structure symmetry paging with ordered UNION ALL |
| `d03595b7a` (2026-10-07) | Optimize pawn symmetry game search with ordered UNION ALL |
| `f1106773c` (2026-10-07) | Search symmetry-expanded pawn structure neighborhoods |
| `89fc82c59` (2026-10-08) | Add features umbrella app with chess core and catalogue sections 1–3 |
| `0ca080a7c` (2026-10-10) | Integrate feature extraction into analysis with per-position vectors |
| `fe859b0a0` (2026-10-09) | Revert slower legal move destination enumeration |
| `5e036e950` (2026-10-12) | Integrate bounded streaming PGN imports with atomic replay batches |
| `2d759de47` (2026-10-12) | Benchmark multi-game PostgreSQL position batching |
| `cb4342222` (2026-10-12) | Add atomic multi-game persistence using shared position batches |
| `aaf6d972f` (2026-10-13) | Report only attacked backward pawns as active targets (feature semantics) |

### Rooms, libraries and the handoff HEAD — 2026-10-13

| Commit | Change |
|---|---|
| `d34536a8e` | Persist rooms and analysis memberships in PostgreSQL |
| `bde0c8680` | Prevent room code collisions when creating rooms |
| `9624fe5e0` | Fix room recovery test navigation and clean up persistent test rooms |
| `8db157fe1` | Share selected analysis position in room links |
| `8bd1d9a93` | Keep room URLs synchronized with selected position |
| `1b2a071d7` | Add read-only room inventory for retention planning |
| `29ffb625c` | Prune expired empty rooms and require creation timestamps |
| `01d0e72e0` | Schedule automatic cleanup of expired empty rooms |
| **`51192f5ac`** | **Add PII-free user identities and linked provider accounts**; latest verified `main` |

Many additional commits exist between these milestones. Use `git log --oneline --all -- <path>` for individual modules rather than assuming the above is exhaustive.

## 3. Benchmark notebook — measured historical results

The numbers here were **reported during earlier development/benchmark sessions**, with fixture qualifications retained. They are **not fresh measurements of HEAD `51192f5`**, are not all from the same hardware or schema, and are not universally comparable. Whenever optimization matters, rerun the repository's benchmark in a disposable database, alternate execution order to reduce cache bias, and record variance/`EXPLAIN (ANALYZE, BUFFERS)`.

### PostgreSQL property query vs earlier disk indices

- PostgreSQL GIN array-property experiment: **1M rows**, 100k matching postings (10% selectivity): table about **51.4 MiB**, GIN index about **1.06 MiB**, total table+indexes about **73.9 MiB**. Depending on query shape, planner chose sequential scan for first-page retrieval and bitmap index scan for counting. Execution was on the order of sub-ms to a few ms for the measured cases.
- **10M rows**, 1M postings (10%): table about **514 MiB**, GIN about **10.3 MiB**, total about **739 MiB**. Some aggregates used parallel plans; measurements were a few to tens of ms, query dependent.
- Earlier homemade posting fetch measured roughly **1–2 µs per posting fetch** in a small disk-index prototype, but not a valid basis for replacing PostgreSQL at scale. Decision: PostgreSQL first; query shape, selectivity, physical IO and planner matter more than isolated posting-fetch microbenchmarks.

### PostgreSQL-native game search

Fixture **10,000 positions, 10,000 games, 10,000 occurrences, 10,000 concrete records**, 1/10 selectivity, page size 100. Measured application SQL vs a joined baseline and full application flow:

| Operation | Application SQL | Joined SQL baseline | Full application flow |
|---|---:|---:|---:|
| First page | **~2.25 ms** | ~1.93 ms | ~2.72 ms |
| Second page | **~3.24 ms** | ~2.86 ms | ~3.12 ms |

**Exactly one SQL query per page** on that benchmark. Before redesign, nested paging had **402 queries for 100 positions** and about **152 ms**; a single joined baseline had around **1.46 ms** in the earlier measurement. Optimization moved high-water bounds/keyset into SQL and occurrence index, maintaining `(position_id, occurrence_id, record row id)` ordering. Full results and current reproduction methodology are in `apps/analysis/benchmarks/game_search_postgres.exs`.

### PGN throughput, parsing and SQL call count

The early batch benchmark used extremely short mainlines (four plies) and should **not** be conflated with subsequent 80-ply realistic fixtures:

| Fixture / run | Observation |
|---|---|
| **1,000 games, bounded** | **14.177 s**, **70.5 games/s**, peak tracked growth **13.18 MiB** |
| **1,000 games, streaming** | **16.071 s**, **62.2 games/s**, peak growth **0.87 MiB**; streaming traded throughput for much lower bounded memory |
| **100,000 games, bounded** | **1,428.709 s**, **70.0 games/s**, peak growth **927.43 MiB**; confirmed need for streaming/batching |

Single-game import SQL profile evolution on **1,000 unique short games** (historical runs; timings also include CPU/parse and vary by run):

| Commit / iteration | SQL queries | Queries/game | Wall clock | Throughput |
|---|---:|---:|---:|---:|
| Initial | 23,997 | ~24 | 13.938 s | 71.7/s |
| `b705bd5` | 19,002 | ~19 | 9.458 s | 105.7/s |
| `cf226b6` | 18,002 | ~18 | 13.561 s | 73.7/s |
| `556211f` | 13,007 | ~13.01 | 9.797 s | 102.1/s |
| `db57425` | 10,007 | ~10.01 | 10.907 s | 91.7/s |
| `b631759` | 7,007 | ~7.01 | 9.085 s | 110.1/s |

**Interpretation:** SQL call count improved significantly, but throughput was **not monotonic**; SAN/parsing/CPU and cache effects mattered. Phase profiles of 1,000 **unique** short games showed parse alone **6.783–9.415 s**, persistence **2.318–2.650 s**, end-to-end **9.695–10.934 s** (~91–103/s). Duplicated fixture in the same development sequence yielded **250–307 games/s** on example runs, with parse ~0.878–2.004 s, persist ~2.015–2.604 s and end-to-end ~2.994–4.120 s across five runs (~242–334/s). Deduplication fixture characteristics massively change results.

**Multi-game position batching experiment, 2026-10-12:** 200 games × 80 plies, 0% duplicates, 3-run experiment (`apps/analysis/benchmarks/pgn_multi_game_position_batch.exs`). One reported run:

| Mode | Wall time | Games/s | SQL queries |
|---|---:|---:|---:|
| Reference per game | **2.700 s** | 74.1 | **1,800** (9/game) |
| Group 1 | 2.535 s | 78.9 | 1,800 (9/game) |
| Group 5 | 1.839 s | 108.7 | 1,000 (5/game) |
| Group 10 | **1.491 s** | **134.1** | **900** (4.5/game) |

Do **not** extrapolate from one run to maximum throughput; production grouped import was later integrated (`cb43422`, `5e036e9`). Re-run `pgn_stream_grouped.exs` and validate complete durable signatures under duplicate/no-duplicate, long game and failure fixtures.

### Pawn structure search and physical-index trade-offs

- Benchmark fixture **1M positions**, **10k symmetry matches** (1/100) or **1k** (1/1000) depending on run, page size 100; tested naive OR vs ordered `UNION ALL` equality scans. Results drove specialized compiler paths; costs/plans depend on selectivity.
- Distance-2 pawn edit-neighborhood fixture: **1M rows**, **10k matching positions** (1/100), **4,022 neighborhood keys**, page size 100. Actual PostgreSQL `EXPLAIN` for a reported first-page plan was about **26.9 ms** and ~22,073 shared buffer hits; this was a performance investigation, not a guarantee that 100M-row queries are already optimized.
- Physical size comparison in a 1M-position production-style fixture: `positions` table **126,033,920 bytes**, pair B-tree index **72,499,200 bytes**, packed expression index **89,366,528 bytes**, record unique index **96,698,368 bytes**. The packed expression representation was exact/collision-free but **larger** than the pair index in that insertion scenario; don't claim packed = automatically faster or smaller. Index experiments are not proof that an optional expression index remains part of the current migration set. Check actual schema (`positions_pawn_structure_index`) first.
- Prefer SQL plans, correctly typed column/parameter expressions and ordered scans over building huge `OR` trees or enormous derived neighborhood materializations. Measure query compile costs separately from SQL execution and complete `PositionStore.page/2`/`GameSearch.page` cost.

### Chess-engine and feature optimizations

- `Chess.Bitboard`, attack tables, king-square lookup, SAN parsing, check detection and sliding rays were independently profiled; commits around 2026-10-09/12 reduced allocations/redundant legal move generation. `fe859b0a0` **reverted** a theoretically attractive but slower legal move destination enumeration. Any new variant must be compared end-to-end, not only in a helper microbenchmark.
- Per-board attack caches and shared bitboards were reused in the new feature catalogue. Tactical/strategic feature semantics were sharpened with regression tests (e.g., isolated/backward pawns count as *active targets* only when attacked). A feature name is not an invitation to broaden semantics without tests.
- Search feature analysis may be computed and versioned per position, but avoid assuming already-proven full-scale indexing for all 21 catalogue sections.

## 4. Alternatives tried, rejected or deliberately deferred

1. **Custom general-purpose PositionDB/GameDB vs PostgreSQL:** earlier file/segment engines included exact posting indexes, recovery markers, DETS and Horde ownership. They were removed after comparing complexity, query composition and scaling with native PostgreSQL. Do not reintroduce multiple authorities.
2. **Two Fly app regions as a substitute for durable replication:** AMS owner + ORD stateless replica/volume route was trialled. Remote LiveView RTT and failover complexity were significant; the deployed architecture is a single AMS app with managed PostgreSQL, not that former distributed store arrangement.
3. **Nested paging / per-position game lookup:** rejected after the ~402-query/152-ms case; moved to PostgreSQL one-query joined paging.
4. **SHA-256 fingerprint as unique canonical identity:** consciously **rejected**; collisions or engineered equality must be disambiguated by full binary game content. Test concurrent inserts.
5. **Keeping all PGN input in memory:** benchmarked bounded vs streaming; streaming reduces memory footprint dramatically at modest overhead. Grouped atomic streaming offers a different throughput/failure compromise; parallel mode deliberately has different failure semantics.
6. **Speculative performance optimizations:** revert when slow (`fe859b0a0`, `be147b082`). The packed pawn expression index was not obviously better than pair indexing in the measured fixture.
7. **Replacing LiveView with SolidJS/React:** prototypes and comparison documents existed, but the merged product retained LiveView and Tailwind v4, with responsive/optimistic UI enhancements. `docs/recon-prototype-to-real.md` contains **stale historical proposals** (including removed PositionDB paths and proposed SPA replacement); do not treat it as the current architecture. `docs/ui-differences-catalog.md` is a historical UI audit; confirm whether entries still apply.
8. **Local email/password user records:** an earlier proposed email-based migration/script was **not the chosen model**. The committed `51192f5` schema deliberately avoids direct identity fields. Likewise, **Better Auth** is an inspiration for the one-User/many-Accounts relationship, **not an installed library**.
9. **Automatic cleanup of every room with analyses:** desirable after libraries and access/recovery semantics exist, but explicitly **deferred**. Current retention only deletes old rooms with no linked analyses.
10. **Built-in Broadway/Oban production ingestion, full semantic plan search, persistent user sessions:** discussed as possibilities, **not verified as shipped**. Inspect current dependencies and tests before proposing a queue or declaring a backend exists.

## 5. Operational and testing lessons

- Repo is greenfield; migrations and APIs can be reshaped directly after inspecting migrations. However, **PostgreSQL constraints, fixtures and serialization boundaries remain critical**; no-backward-compatibility does not mean casual data loss in development/prod or untested migrations.
- Native PostgreSQL on the developer workstation; **no Docker dependency for local DB**. `config/test.exs` rejects test DB paths other than `/openchesslab_test`. Multiple umbrella test helpers `TRUNCATE ... RESTART IDENTITY CASCADE` on startup, so tests must never point at dev/prod or run concurrently sharing one test DB without isolation.
- Intermittent historical test failures exposed shared durable room IDs, races in concurrent canonical inserts, nondeterministic tests and missing test cleanup. Tests were adjusted to isolate room IDs, use `on_exit` for persistent rooms and assert real persistence. Flaky reruns do not remove the need for deterministic fixes.
- SQL isolation/concurrency matters: unique constraints, atomic deduplication/insert, advisory locks, transaction boundaries and `SKIP LOCKED` for pruner. Record IDs and analysis IDs are text, not interchangeable with DB integer IDs.
- User preferred **Quokka over Styler**, consistent formatting from umbrella root, direct English Git commit messages and complete copy/pasteable outputs. Earlier `Get-Clipboard | git apply` patches failed with garbage/corrupt patches; generated PowerShell scripts also failed once due to wrong string anchor/here-string newline formatting. Prefer robust, verified atomic scripts or full files; validate against HEAD and partial worktree state.
- Deploy is **manual**. Production Fly health checks `/health` and `/ready` were green after the cutover; release migration command and MPG connection selection are in `fly.toml` / `config/runtime.exs`. Earlier pgbouncer DNS resolution failed (`:nxdomain`) and was addressed with direct endpoint + IPv6 socket options.
- Windows PowerShell and Arch Linux both need supported instructions; no reliance on fixed user paths. Elixir/OTP/Tailwind versions may change: follow current `mix.lock`, `mix.exs`, Dockerfile and available toolchain. Use Git to verify any mentioned SHA is current.

## 6. Privacy and authentication decision log (particularly important)

**User requirement, 2026-10-13:** *prefer not to store any personally identifiable information*. External providers, especially **Lichess**, should authenticate users and eventually allow access to their own studies/played games. The model is **one User to many Accounts**, inspired by Better Auth's relationship, not its implementation. The prior Blunderfest reference commit [`d615f973b6b9fd40662f2952ddcd8eadf8d1bdb7`](https://github.com/blunderfest/blunderfest/commit/d615f973b6b9fd40662f2952ddcd8eadf8d1bdb7) implements a **historical in-memory anonymous profile** with server-generated names and salted hashes of per-device secrets; it also discusses future keyed external provider identifiers. That project is an inspiration, **not** source code to copy verbatim into OpenChessLab or evidence that OpenChessLab has anonymous identities today.

**What shipped in `51192f5`:**

- `users` holds only UUID and creation timestamp.
- `accounts` holds `(user_id, provider, subject_hmac)` with unique provider+digest; multiple providers per User; no stored raw subject, email, provider username or OAuth token. `Analysis.Accounts` computes keyed `HMAC-SHA256(provider <> 0x00 <> subject)`; only **trusted verified subjects** should ever reach it.
- `user_analyses` references existing analysis IDs with unique `(user_id,analysis_id)`; a shared analysis need not be cloned. Deleting a User removes membership records; deleting an analysis cascades its library memberships.
- Local dev/test HMAC keys exist, **production key still must be provisioned and kept stable** ahead of OAuth. Users/Accounts/UserLibrary APIs have **no session or authorization enforcement**: they are trusted domain operations and must not be exposed directly to untrusted clients.

**What must be designed next:**

1. Lichess OAuth2 authorization-code + PKCE S256 + state/CSRF/replay protection; verify provider identity using current documentation, never trust a user-supplied `subject` or callback claims without exchange/verification.
2. First-login User creation vs lookup of existing account; explicit provider account linking to an **already authenticated** User; no automatic merge by email/name. Error/conflict path for an account already owned by another User.
3. Secure, revocable server-side session binding Phoenix/LiveView to a User. Add session storage only if the design calls for it; `user_sessions` is a **proposal**, not a table at HEAD.
4. LiveView personal library: save from a room, list/open existing analyses without a room code, remove a bookmark without deleting shared content, separate read/write/share permissions. Existing `RoomLive` still allows link-based guests; plan migration of anonymous work only if needed.
5. Lichess study/game data APIs and scopes: public vs private access, `study:read` when required according to current Lichess docs, import/sync format (study variations/comments → analysis tree; games → canonical games + records), provenance and deletion handling. If durable access tokens are necessary, **encrypt separately**; `account_grants` was discussed but has not been added.
6. Independent lifecycle/garbage collection: rooms may eventually expire despite containing analyses, but only after users can find/bookmark analyses independently and permission/retention policy has been tested.
7. Privacy threat model: HMAC identifiers remain pseudonymous; game records can carry real player names/metadata; comments and imported studies can include personal data. Verify logging/retention/deletion behavior, HMAC key rotation, OAuth scope minimization and whether stronger data-minimization policies are needed. Do not promise literally zero PII globally just because the identity tables exclude direct identifiers.

## 7. Open work, in suggested order

### First authentication foundation slice — 2026-10-13

Starting from clean local `main` at `f1ed0a006dbdee299da1eb74d8315b2c9378b75b`, add revocable PostgreSQL user sessions before exposing OAuth routes. This makes expiration, logout invalidation, user deletion and transactional issuance independently testable. The implemented contract and privacy limits are in architecture section 6. No new dependency, browser authentication, OAuth grant storage or account linking endpoint is introduced.

Official Lichess documentation checked on 2026-10-13: [authorization request](https://github.com/lichess-org/api/blob/master/doc/specs/tags/oauth/oauth.yaml), [token exchange/revocation](https://github.com/lichess-org/api/blob/master/doc/specs/tags/oauth/api-token.yaml), [authenticated profile](https://github.com/lichess-org/api/blob/master/doc/specs/tags/account/api-account.yaml), and [authentication overview](https://github.com/lichess-org/api/blob/master/doc/specs/lichess-api.yaml). The documented flow uses `https://lichess.org/oauth`, S256 PKCE and independent random state; form-encoded `POST https://lichess.org/api/token` requires the original client ID, redirect URI and verifier. `GET https://lichess.org/api/account` accepts an OAuth bearer token without additional scopes. Lichess supports public clients without a client secret; refresh tokens are not supported. Authenticate with no extra scopes; study/game import remains separate.

Implementation order after this slice:

1. **Implemented in the next slice below:** short-lived OAuth attempts with independent state and PKCE verifier, browser-token binding, atomic single-use consumption and cleanup. HTTP cookie/route integration remains in step 3.
2. **Provider exchange/verification and atomic user resolution now implemented below:** stable production account HMAC secret configuration remains required before enabling login.
3. Integrate login/logout with the session store, session renewal against fixation, secure cookies, CSRF-protected initiation/logout and protected LiveView mounts/events. Add expired-session cleanup before public login. Account linking must require an existing authenticated session plus fresh provider verification; never merge by name/email.
4. Personal library LiveView using the server-resolved user, with cross-user access tests. Keep guest rooms available. Request import scopes only in a later, separate consent flow.

### OAuth attempt foundation slice — 2026-10-13

Starting from clean `main` at `2ba37c20ee2533545301e267eb6d99afddcd5e99`, implement the pending Lichess login handshake in `Web.LichessOAuthAttempts`. Use existing Phoenix encryption for a browser-held verifier rather than retaining a decryptable verifier in PostgreSQL; keep PostgreSQL authoritative for single-use state. A single autocommitted deletion prevents concurrent callback replay, and consumption rejects surrounding transactions to prevent a later login rollback from restoring an attempt. Detailed contracts, five-minute expiry, cleanup and integration requirements are in architecture section 6. The official authorization-request specification above was rechecked for independent random state/verifier and S256. Provider exchange, public routes, actual cookies and account linking are still separate work.

### Verified provider exchange slice — 2026-10-13

Starting from clean `main` at `071d3e3208af09e0eb96c6c89c85f9c3e11b01ee`, connect single-use attempts to Lichess token exchange, authenticated account-ID extraction and token revocation. Rechecked the official token/account schemas linked above and the [OTP HTTP client documentation](https://www.erlang.org/doc/apps/inets/httpc.html), including the installed OTP source. Use the existing OTP client with explicit security options instead of adding a Hex dependency. Require confirmed token revocation before returning a verified identity; failures return fixed error atoms. Test both controlled provider responses and the real HTTP client against a local fixture. Architecture section 6 records the complete contract and its limits. Public routes, browser authentication, account creation/linking and HMAC-secret provisioning are still separate work.

### Atomic account-resolution slice — 2026-10-13

Starting from clean `main` at `a76b39e0f87b5bc029d4a1c8f536a7c2a211f5f7`, add `Analysis.Accounts.resolve_verified/2`. Keep first-login user creation separate from explicit account linking and rely on the existing PostgreSQL unique constraint to arbitrate races. The conflicting insert returns the existing owner without transferring the account, and the unused candidate user is removed in the same transaction. Tests force eight concurrent first-login writes to overlap, check racing explicit linking, HMAC-only persistence, invalid input/configuration, and joint User/Account/session rollback. Architecture section 6 describes the contract. No new migration, provider API, authentication route or dependency is introduced.

### Authentication runtime-configuration slice — 2026-10-13

Starting from clean `main` at `a0abd774891558cc1431af0588d3b8bd19ef42e7`, load a stable Base64-encoded identity HMAC secret and an optional, complete Lichess client-ID/callback pair from environment variables. Reuse the provider client's configuration validation, require HTTPS and an explicit HMAC key for production Lichess configuration, and fail with value-free errors for invalid/partial settings. Tests evaluate the real runtime file, including production requirements, the 32-byte secret boundary and loopback development callbacks. Rechecked the official authorization specification linked above. Architecture section 6 defines the variables and generation procedure. No production secret is set, no deployment is performed and no browser route is exposed.

### Browser-bound login-initiation slice — 2026-10-13

Starting from clean `main` at `cfa146f088d5884f1514b98ba708af6d26722d70`, add CSRF-protected `POST /auth/lichess`, the five-minute HttpOnly/Secure/SameSite=Lax browser cookie and the fixed Lichess PKCE authorization redirect. Rechecked the official authorization request above. Tests obtain real CSRF/session cookies through the home page and explicitly remove ConnTest's default CSRF bypass; they verify browser binding, ignored attacker parameters, no identity/session writes, cookie security and disabled configuration. The initial GET test incorrectly expected an exception alongside 404; the assertion was corrected to check the actual 404 response. Architecture section 6 records the boundary and development cookie exception. Callback/login/logout and session cleanup remain pending, so there is no public login button or recommended production OAuth deployment yet.

### Browser callback/session slice — 2026-10-13

Starting from clean `main` at `43a0ca666f147b746ab5f3815f53f524fbf349b0`, connect the browser-bound callback to provider verification and transactional account/session resolution. Recheck the official token and authenticated-account specifications linked above. Renew/clear the browser session and CSRF state on success, revoke the previous session credential in the same transaction, encrypt the browser cookie and compile production Secure=true independently of proxy scheme. Filter sensitive OAuth parameter logs. Boundary tests include a real PostgreSQL insert constraint failure to prove joint rollback without restoring consumed state. Correct misplaced module aliases and the locale-key test assertion found by initial test runs. Architecture section 6 describes contracts and remaining deployment prerequisites.

### Friendly room display-name slice — 2026-10-13

Starting from clean `main` at `a6636d38e9f7a363f64d988241b79c880f124904`, replace hexadecimal `Guest` labels with the user's Blunderfest-style curated adjective/animal/two-digit generator in `Web.DisplayName`. Keep labels ephemeral and independent of OAuth, with existing participant IDs supplying identity rather than name uniqueness. Tests check curated output and real LiveView presence/chat author integration. No schema change, provider data or dependency is added. This visible room improvement can be deployed while production Lichess configuration remains absent; complete public authentication still needs logout, cleanup and authenticated UI/access handling.

The user reported a manual deployment after `118a47b` on 2026-10-13.

### Browser logout slice — 2026-10-13

Starting from clean `main` at `118a47bb930c70acba335b4eadc7ee38c92276b2`, add CSRF-protected `POST /auth/logout`. Revoke the protected browser's credential before clearing session/CSRF state and expiring both session and OAuth-attempt cookies. Tests verify isolation from other sessions/users, real CSRF enforcement, safe anonymous/repeated/expired logout and a retained encrypted cookie whose revoked credential fails PostgreSQL resolution. Architecture section 6 records the contract and pending LiveView authorization/disconnection work. No dependency, migration or deployment is introduced.

### Expired-session cleanup slice — 2026-10-13

Starting from clean `main` at `766aafca17200869be0d43424722272976046bf7`, add PostgreSQL cleanup of at most 1,000 expired sessions per pass and the matching expiry/token-hash index migration. Supervise a production worker with a one-minute initial delay and hourly passes, keeping failures sanitized and scheduling recovery. Tests cover active-session preservation, locked rows, concurrent passes, bounded draining, timer replacement, migrated index and recovery after a database failure. Architecture section 6 records the cleanup contract and its retention limits. No provider grant, dependency or deployment is introduced.

### Optional browser/LiveView authentication slice — 2026-10-13

Starting from clean `main` at `e8422fa2fde7aedc74de7a3e25e8b13e7839cc96`, resolve protected session credentials into a server-side `current_user` on browser requests and independent LiveView mounts. A LiveView event hook rechecks PostgreSQL before each handler, so expiry/revocation clears the identity rather than trusting cached User data. Tests cover real router mounts, guest rooms, replayed cookies, disconnected-to-connected revocation and malicious request/event identity assertions. An import conflict in the test fixture was fixed by qualifying its Component assign calls. Architecture section 6 defines the contract and separates optional identity from future private authorization. No migration, dependency or public login UI is introduced.

### Active browser-session disconnection slice — 2026-10-13

Starting from clean local and remote `main` at `4583a13b76b62163f9ccf9dfee3beb383f434dc4`, use Phoenix's existing session-specific transport disconnect mechanism for logout and successful login replacement. Inspect the installed Phoenix/LiveView source to verify socket topic subscription and transport shutdown. Publish only after revocation commits; preserve other credentials and failed logins. Tests exercise two actual transport callback lifecycles, session isolation, guest reconnection and provider/database failure paths. Architecture section 6 records the limits of transient notifications and direct domain revocation. No schema, dependency or deployment change is introduced.

### Login/logout interface slice — 2026-10-13

Starting from clean `main` at `d9585422a8f2d6ca06b932d153780d831f4258d9`, add native CSRF-protected login/logout forms to the shared header. Gate login on trusted OAuth configuration, derive logout from the resolved User, translate controls and fixed callback errors, and show failures in the layout. Tests exercise the rendered forms against actual CSRF enforcement plus both public routes, English/Dutch labels, disabled configuration and event-time revocation. No schema, dependency, private library or deployment change is introduced.

Validation: disconnection slice 30 targeted / 141 full web tests passed; UI slice 16 targeted / 146 full web tests passed. `mix assets.build`, root formatter verification and `git diff --check` passed. A sandbox hard-link permission error prevented one Mix invocation from starting; the same command completed outside the sandbox. The analysis suite was not rerun for these web-only changes; its accepted flaky-test backlog remains below. Provider responses were fixtures; a real Lichess login and production deployment were not performed.

### Authentication redirect preference rendering — 2026-10-13

The user deployed `49385c1` and verified production login, logout and disconnection across tabs after the three Fly authentication settings were provisioned. The user then reported light-to-dark and English-to-Dutch flashes on login/logout. The initial HTTP render had no access to localStorage and both LiveViews mounted with the system theme. Add allowlisted presentation cookie mirrors that survive authentication session resets, initialize mounts from those preferences, and apply theme variables to the document root. Initial regression assertions incorrectly assumed Phoenix omitted its `phx-r` root attribute; replace exact opening-tag matching with parsed DOM attribute checks. No schema or authentication-policy change is required; deployment of this fix remains a separate manual action.

Validation: 25 targeted and 150 full web tests passed, plus four Node tests for preference cookie persistence/validation and blocked storage. Asset build, formatter verification and `git diff --check` passed. As in the previous slice, the asset build required execution outside the sandbox after Mix's hard-link lock was denied.

### Authenticated library list slice — 2026-10-14

The user confirmed the preference fix in `2708819`. Starting from clean local/remote `main` at that commit, add a private `/library` list with HTTP and LiveView mount/event/navigation guards. Scope every query/mutation to the credential-resolved User and remove only personal references. Add bounded keyset paging over the existing user/analysis unique index, without loading analysis trees. The initial page exposes reference identifiers and saved dates; save/open flows remain next slices. No migration or production deployment is included.

Validation: 10 targeted identity tests and 17 initial auth/library tests passed; the additional paging interaction test is included in the full suite. Full analysis seed `398267` passed all 590 tests. Full web seed `511632` initially passed 158/159: the earlier login-control test simulated OAuth denial without its state, leaving an attempt that contaminated a later empty-table assertion. Supplying the real generated state fixes the fixture at its source; all 159 web tests then passed with the same seed. This is separate from the accepted analysis `:invalid_occurrences` backlog.

### Personal room-analysis copies — 2026-10-14

Starting from clean `main` at `542c757`, implement the user's explicit-copy decision: solo continuations must not silently alter an earlier shared analysis. Add an authenticated room save button, transactional snapshot creation and a library association, with English/Dutch explanation and feedback. Keep canonical content reusable and mutable trees independent. Architecture section 6 records the transaction and access contract. No migration or production deployment is included.

Targeted tests cover full aggregate preservation, divergence in both directions, deletion of the original without losing the copy, concurrent copies, absent/removed memberships, a real database constraint failure after the copy insert, credential revocation and forged parameters. Initial web fixtures expected a direct mount despite the existing room selection redirect; they were corrected to use canonical selected-analysis URLs and verify the HTTP redirect for an unrelated ID. The private-ID selection test also covers a corrected error-notice shape in the existing selection handler.

Validation: 14 targeted domain tests and 13 targeted web tests passed. Full analysis seed `398267`: 594 passed; full web seed `511632`: 163 passed. Root formatting verification, asset build and `git diff --check` passed. The build required execution outside the sandbox because Mix's temporary hard-link lock was denied. The accepted analysis-suite backlog remains unchanged.

Reproduce from the umbrella root in either PowerShell or Bash (run serially):

```text
mix format --check-formatted
cd apps/analysis
mix test --seed 398267
cd ../web
mix test --seed 511632
mix assets.build
cd ../..
git diff --check
```

Commit subject: `Add personal analysis copies from rooms` (commit/push performed by Codex under the user's existing authorization; production deployment remains manual).

### Compact header and portable handoff — 2026-10-14

After the user deployed `7ea45e1`, group the home/room header into a single theme-cycle button, Help (shortcuts/tour) and Account (login or library/logout). Reuse preference persistence and CSRF-protected forms. Native disclosure menus close with Escape/outside clicks. Correct the mobile piece-set dropdown alignment after browser inspection. Add `docs/HANDOFF.md` as the maintained cross-laptop/OpenCode Go entry point.

Validation: 11 targeted auth/preference tests and all 165 web tests passed (full seed `511632`). The initial new test incorrectly treated a LazyHTML selection as a list; corrected it to inspect selected IDs. Browser checks covered desktop account/help, mobile 360px layout and light/dark switching. Formatter, asset build and diff checks passed. The build initially required sandbox escalation and hit an approval-service usage limit; it succeeded after the user reported that limit lifted. No domain/schema change; the analysis suite was not repeated. Production deployment remains manual.

### Private personal editor — 2026-10-14

Starting at `63acd64` with only the user's Medium model-advice change in HANDOFF,
add `/library/:id` and a separate private board/tree editor. Library membership alone
does not imply privacy: deny room-linked or multiply referenced analyses. Lock the access
scope through each domain operation, check the displayed revision and preserve independent
room/copy content. No schema, implicit room, sharing or retention change.

Targeted coverage includes foreign/absent IDs, removed memberships, room/shared references,
concurrent revision conflicts, failed edits, credential expiry/revocation, persistent moves,
comments/NAGs, variations and explicit pawn promotion. The first targeted web run passed
16/17: its conflict test found the warning was cleared on a URL patch. Preserve the notice
through handle_params; the same seed `262747` then passed 17/17, and the two additional
variation/promotion tests passed in the 10-test editor file. Full analysis seed `398267`: 599 passed.
Full web seed `511632`: 175 passed. Asset build (outside the sandbox for Mix's hard-link lock),
formatter and diff checks passed. Production deployment remains manual.

### Home entry controls and independent cards — 2026-10-14

After private editor commit `05c3cf6`, the user requested hiding piece selection and Help
on the boardless homepage, aligning Create room with the room-code input, and preventing
Join errors from moving Create controls. Limit header Help/piece controls to room workspaces;
remove homepage handlers that opened irrelevant tour/shortcut dialogs. Align fixed-height action
rows beneath description space and let cards size independently. The room controls stay available.
Targeted home/auth/preference tests: 15 passed. Browser checks cover English/Dutch desktop,
identical 56px action heights/tops, unchanged Create button/caption positions after an unknown
code, and Dutch 360px mobile without horizontal overflow. Full web seed `511632`: 175 passed;
asset build, root formatter and diff checks passed. Analysis tests were not repeated for this web-only slice.
No database change or production deployment; temporary local preview server stopped.

### Personal library titles — 2026-10-14

After the user confirmed deployment of `561ed67`, start from its clean main checkout and
add personal labels to saved library references. A nullable, length-constrained title column
keeps paging bounded without decoding trees. Rename uses only the verified User and the
server-selected current-page entry; the same title appears in the private editor. Room content,
other users' labels and aggregate revisions remain independent. Blank titles reset the fallback.
No provider import, sharing, retention or automatic title generation is added.

Dev migration succeeded; the first test migration hit the sandbox Mix hard-link restriction.
Tests were mistakenly started before correcting that migration, producing 9/13 passes with
four missing-column errors. Run the migration outside the sandbox; the same seed `96633`
then passed all 13 targeted domain tests. The 23 targeted web tests passed, covering persistent
labels, escaped output, Dutch controls, clearing/cancellation, removed references, forged
parameters and revoked credentials. Database suite: 4 passed, including release migration idempotence.
Full analysis seed `398267`: 602 passed; full web seed `511632`: 179 passed.
Asset build (outside sandbox), root formatter and diff checks passed. No production deployment;
the normal release migration must apply the new column before the new app code starts.

**Near-term (next green vertical slices):**

- **OAuth security foundation:** production login/logout and cross-tab disconnection have been user-verified. Private library routes/events now require a valid session. Explicit provider account linking and private analysis editing/sharing policies remain separate work.
- **Lichess first-provider login:** provisioned and verified; distinguish any future provider account linking from requesting study/game scopes.
- **Library access in LiveView:** authenticated listing/removal, personal titles, independent copies and private editing exist. Next add private position setup/tools and explicit copy-back sharing. Never reopen a personal copy by silently adding it to a shared room.
- **Tests / infra:** update auth/migration/release coverage, health/readiness where relevant, and test helpers for new tables; check app scopes and prevents accidental access to other users. Keep manual production deployment.
- **Accepted test backlog (2026-10-13):** investigate suite-dependent `:invalid_occurrences` failures in `Analysis.AnalysesTest` (`test/analysis/analyses_test.exs:122`) and `Analysis.PgnBatchImporterTest` (`test/analysis/pgn_batch_importer_test.exs:143`). Full analysis seed `938846` produced 588/589, then 587/589 passes; the isolated analysis test passed and both files together passed all 63 tests with that same seed. Full seed `824219` passed all 589. Shared PostgreSQL fixtures/reset order are suspected, but the cause is not established. The user explicitly requested putting a flaky test on the backlog. Do not suppress the tests or describe the failing seed as green. Reproduce from `apps/analysis` with `mix test --seed 938846`; compare `mix test test/analysis/analyses_test.exs test/analysis/pgn_batch_importer_test.exs --seed 938846` (same commands on Windows/Arch).

**Subsequent design and scaling:**

- Study/party import and sync from Lichess with provenance, safe minimal provider grants, trees/metadata mapping and error/retry semantics.
- Rework room retention after users can save/find analyses independently. Design what happens to unclaimed/orphan analyses, active-but-empty chat rooms, and share links; specify deletion semantics separately for rooms, bookmarks and analysis records.
- Bulk import at millions-of-games scale: repeat benchmark on representative PGN lengths, concurrency/window sizes and duplicates; investigate ingestion queue only when a concrete use case warrants one; preserve atomic batch vs parallel failure contracts.
- Indexed execution of catalogue-based positional plans and similarity queries at ≥100M positions; develop cardinality/query planner strategy and benchmark on production-shaped PostgreSQL tables. Existing `Features.compare/2` is not an indexed corpus search.
- Eventual per-user visibility, collaboration roles and room authority; signed/opaque share capabilities as needed. Current room code is a bearer link; do not present role isolation as implemented.
- SAN localization/i18n, frontend UX debt in the historical UI catalogue, observability of import/query/pruner/SAN hot paths, and scalability of single AMS deployment. Select priorities through small tested slices rather than a speculative rewrite.

## 8. Verification checklist for incoming Codex session

1. `git status --short`, `git rev-parse HEAD`, `git log -12 --oneline`; compare to handoff baseline `51192f5ac` (it will move).
2. Read `AGENTS.md` and `docs/architecture.md`, then relevant source/migrations/tests, not outdated prototype notes.
3. Check `apps/database/priv/repo/migrations/20261013160000_create_users_accounts_and_user_analyses.exs`, `apps/analysis/lib/analysis/{users,accounts,user_library}.ex`, `apps/analysis/test/analysis/user_identity_test.exs` for auth baseline.
4. Inspect `apps/web/lib/web/router.ex`; at baseline there are **no** OAuth/session/library routes. Examine `config/runtime.exs` before adding production secrets.
5. For import/search read `pgn_batch_importer.ex`, `game_records.ex`, `position_store.ex`, `game_search.ex`, current tests and benchmark fixtures; distinguish tested APIs from intended UX.
6. Run targeted tests and relevant suites using **test DB only**, format at umbrella root (Quokka), and `git diff --check`.
7. Start each implementation response with an immediate **English commit message**, deliver a complete vertical slice, provide Windows PowerShell and Arch Linux commands, wait for confirmed green results, and deploy only on explicit request.
