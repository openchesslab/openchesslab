# Performance: cross-region rapid play (ord LiveView ↔ ams room)

Findings and measurements from the rapid-move investigation (2026-09-29/30),
which produced the server move-path and client pending-queue changes.

## Context

- Clients connect to their nearest Fly region; rooms live on the node that
  created them. A US client on `ord` interacting with a room on `ams` pays a
  cross-region round trip for every call from the LiveView (ord) to the
  room/analysis processes (ams).
- Measured **per serialized cross-region call: ~230 ms** (GenServer call through
  the Horde-registered stores/room processes, ord ↔ ams). Client ↔ ord
  LiveView round trip: **~195 ms** (assign-only handlers).
- Production baseline recorded with Playwright against a deliberately
  cross-region room (`fly-prefer-region: ams` for creation, `ord` for
  browsing; tooltip confirmed "You are connected to ord; the room runs in
  ams"), using `page.on("websocket")` frame timing plus a board
  MutationObserver for the DOM timeline.

## Baseline (before)

Production, ord LiveView / ams room, empty→N-node trees:

| Operation                                | Time      | Cross-region calls |
| ---------------------------------------- | --------- | ------------------ |
| select piece / toggle orientation        | 194–223 ms | 0 (assign only)   |
| annotation (square/arrow)                | 202 ms     | 0 (assigns+presence) |
| play move, 0 existing nodes              | 2292 ms    | 9                  |
| play move, 1 node                        | 2585 ms   | 10                 |
| play move, 2 nodes                       | 2840 ms   | 11                 |
| play move, 3 nodes                       | 2986 ms   | 12                 |
| navigate path, 4-node tree               | 1517 ms   | 6                  |
| post-move self-refresh (out-of-band diff)| ~830–990 ms | ~4–5+N (blocks the next queued interaction) |

The move-ack times fit `client_rtt + 230 ms × (9 + N)` almost exactly, which
is what identified the call count. A selection clicked immediately after a
move took **1300 ms** instead of ~200 ms because it queued behind the
post-move self-refresh.

### Where the 9+N calls came from (one logical move)

`maybe_play_move` → `Analyses.play`:

1. `AnalysisStore.get` (fresh analysis + revision) — legitimate
2. `PositionStore.get` (source node's position) — legitimate
3. `PositionStore.append` (result position) — legitimate
4. `AnalysisStore.update` (persist tree) — legitimate

Then `update_analysis`:

5. `refresh_room` → `Rooms.get` (room server) — redundant: room membership
   does not change on a move
6. `room_analyses` → `Analyses.get` per analysis in the room — redundant: the
   move already returned the fresh analysis and revision
7. `set_analysis` → `current_position` → `PositionStore.get` — redundant: the
   position was just computed/stored by the move
8–9+N. `set_analysis` → `move_list_data` → one `PositionStore.get` per tree
   node (root + N) — redundant: positions are immutable and content-keyed

Then, asynchronously, every write published `{:analysis_changed, id}` and the
LiveView re-fetched and re-rendered **everything it had just rendered**
(another ~4–5+N calls, ~1 s), delaying every interaction queued behind it.

### Client-side failure under pending moves

Reproduced on production and locally with `Process.sleep(2400)` in
`maybe_play_move/4`:

- Any plain click on a piece ran `pointerDown` → `pointerUp` (no movement) →
  `clearDragPreview()`, which removed the pending move's ghost **and un-hid
  its source**: selecting the next piece visually cancelled the pending move
  (snap-back of a move that was actually being processed).
- `clickToMove` returned early while a move was pending → no optimistic hold
  for subsequent click-to-move moves.
- A second pending move **reused the first move's ghost**, showing the wrong
  piece.
- No speculative board state: moves 2 and 3 showed nothing until their acks
  (2.4–15 s later). Entering 3 moves took ~11.5 s to fully land.

The original hypothesis — that the next move is rejected against a stale
`socket.assigns.position` — was **disproved**: the LiveView mailbox serializes
events, so each move was validated against the post-previous-move position
and every rapid move landed correctly server-side even before the fix. The
server was correct but slow; the client was broken.

### A LiveView constraint discovered along the way

Hook `pushEvent` locks the hook's element (`putRef([el: loading, lock: true])`
→ `data-phx-ref-lock` + a cloned tree) for the in-flight event's duration.
The Board hook's element is the whole board, so while any hook-pushed move is
in flight, board-component patches are silently deferred
(`DOMPatch`: "leave the visible DOM locked and wait for a later patch") and
their diffs merge into the next unlocked patch. Consequence: during a burst of
hook-pushed moves, intermediate board patches apply only when the **last**
reply unlocks the board. The client's settle logic is deferral-aware because
of this (see below).

## Fixes

### Server — one move ack = exactly 4 cross-region calls, no follow-up

1. **Revision on the change event** (`AnalysisEvents.publish_changed/2`,
   `Analyses.persist`): `{:analysis_changed, id, revision}`. The LiveView
   skips the refresh when `revision <= analysis_revision` — its own write (or
   an older concurrent one) is already in hand. A revision-less clause covers
   mixed-version nodes during a rolling deploy.
2. **Local sidebar patch** (`update_analysis`): a plain mutation only bumps
   this analysis's revision; the sidebar entry is rebuilt via
   `AnalysisView.analysis_detail/3` from the analysis already in hand instead
   of re-fetching the room and every analysis in it.
3. **Position cache per LiveView** (`AnalysisView.current_position/3`,
   `move_list_data/3`): positions are immutable and keyed by exact content, so
   repeated renders reuse the cache. The cache is pruned to the currently
   rendered tree (removed subtrees and other analyses don't linger).
4. **Result-position seeding** (`RoomLive.seed_result_position/4`): the
   position resulting from a move we just validated against is deterministic,
   so it is seeded into the cache instead of re-fetching it for the render
   that follows. Guarded by the source node's position id: if a concurrent
   promote/remove restructured the tree so our rendered position no longer
   backs `current_path`, it falls back to fetching.

Measured after (counting proxies forward to the real clustered stores and
count; see `apps/web/test/support/cross_region_counters.ex`): per move —
`analysis:get` 1, `analysis:update` 1, `position:get` 1, `position:append` 1.
**4 calls, constant regardless of tree size, no follow-up refresh.**
Production estimate: `195 + 4 × 230 ≈ 1.1 s` per ack (was 2.3–3.0 s growing
with tree size, plus ~1 s follow-up). The regression test asserts these exact
counts and was verified to fail against the old behavior.

### Client — per-move pending queue, no JS chess rules

- **Pending moves are a queue**: each move gets its own ghost (with the piece
  it moved) and hides only its own source square; a plain piece click only
  ends the *active drag preview*, never a pending move's hold.
- **Client-side selection for click-to-move** (`data-spec-selected`, same
  cyan treatment as the server-rendered selection): the source click is
  remembered locally (only pieces of the speculative side to move — derived
  from the server-rendered `data-side-to-move` plus the pending count), so
  the target click can play optimistically without waiting for the
  cross-region selection round trip. The target click is hijacked
  (`stopPropagation` + the hook's own `board-square` push, identical event
  and payload) so it gets a reply callback; the native phx-click still fires
  for source clicks so the server selects authoritatively.
- **Gated by `data-play`**: the server renders it only while square clicks
  route to move playing, so the position editor and the setup board keep
  their native flows (no ghosts, no hijack).
- **Reconciliation**: a pending move is confirmed when a patch puts a piece
  on its target while its source is empty (the ghost is removed exactly when
  the real piece appears). The reply callback settles a move; while any later
  move is still awaiting its reply (its board lock may be deferring patches),
  nothing rolls back — only once every reply has arrived does an unreflected
  move mean it was not played (rejected / conflict / promotion choice
  showing) and the speculative visuals roll back to the server's board. A
  12 s per-move safety net covers replies that never arrive.
- **Ordering**: the LiveView processes all pushed events in click order, so
  each move is validated against the moves before it; the client never
  decides legality. Ordering comes from the channel, not from client state.

## Verification

- `mix test apps/web/test --seed 0` — 74 passed, including:
  - exact per-move cross-region call counts (fails against the old behavior),
  - remote-revision refresh still propagates to other LiveViews,
  - the optimistic-move board contract attributes (`data-play`,
    `data-side-to-move`, `data-piece-color`; absent in editor/setup mode).
- `mix test apps/analysis/test --seed 0` — 425 passed (event shape + publish
  revision).
- `mix format`, `mix assets.build` — clean.
- Playwright against localhost with a temporary 2400 ms simulated move path:
  - 6-click opening sequence (and a mixed clicks+drags burst) entered in
    ~0.7–1.1 s; the board showed the speculative sequence immediately
    (per-move ghosts with correct pieces, sources hidden); converged with no
    snap-backs, stuck ghosts, stale selections or duplicate pieces
    (`1. e4 e5 2. Nf3 Nc6 3. Bc4`, black to move).
  - illegal move during a burst: toast immediately, ghost rolls back when the
    burst settles; legal move played correctly (server was right).
  - promotion (a7→a8, pick queen), position editor and setup-board guards,
    optimistic arrow/highlight → authoritative `data-shape-key`, and
    single-move behavior all verified unchanged.

## Intentionally not solved here

- The remaining ~1.1 s production ack: 4 legitimate cross-region calls in
  `Analyses.play` (analysis get / position get / position append / analysis
  update) + ~195 ms client RTT. Going below 4 needs domain-contract changes
  (trust the LiveView's cached analysis/position with conflict retry) or
  RPC batching/co-location — judged a redesign, out of scope.
- The per-call ~230 ms ord↔ams latency (network + Horde resolution) is
  untouched.
- During a burst, intermediate board patches (including the server's legal
  target dots and selection highlight) defer to the last reply (board lock).
  Instant legal targets would require client-side chess rules — deliberately
  not introduced.
- `/health`-level stuff, deployment topology, and room ownership remain as
  they were.

## Production verification checklist (after deploy)

1. Single move ack on an ams-room/ord-client path: expect ~1.1 s (was
   2.3–3.0+ s), and no second out-of-band patch after the ack.
2. Rapid opening sequence (drag or click-click): enter several moves
   immediately; ghosts appear instantly; clean convergence.
3. Illegal move while others are in flight (toast + rollback).
4. Two browsers: remote moves still propagate; the sidebar "rev N" still bumps
   per move.
5. Regression watch: position editor / setup boards (no ghosts on clicks) and
   the promotion dialog.
