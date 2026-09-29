# Phase 0 recon: prototype → real implementation

This document is the migration map from the SolidJS SPA prototype at
`/tmp/opencode/prototype/` to the real implementation that will replace
`apps/web`'s LiveView. It was written after reading the existing
`apps/analysis` and `apps/web` code; treat it as a starting point that
the team should adjust.

## What the existing app does

### `apps/analysis` — the analysis domain

| Module | Responsibility |
|---|---|
| `Analysis.Analysis` | Tree of `Node` with `position_id`, `transition`, `comment`, `children`. Path-based addressing: a node is identified by a path `[i, j, k]` from the root. The main continuation is `children[0]`; siblings `1..n` are variations. |
| `Analysis.Node` | Single occurrence: `position_id` (lookup into PositionStore), `transition` (move or edit), `comment`, `children`. |
| `Analysis.Transition` | Either `{:move, Move.t()}` or `:edit`. |
| `Analysis.Analyses` | Public API. `create / get / list / play / edit / promote / remove / set_comment / create_from_game`. All mutations go through `persist/2` which uses the analysis store's revisions. |
| `Analysis.AnalysisStore` | Revisions-based optimistic concurrency. Behaviour: `Memory` adapter in tests; `DETS` adapter for persistence. Distributed via `Horde.Registry` (`Analysis.AnalysisStoreRegistry`). Owner node can be configured via `Analysis.AnalysisStoreOwner`. |
| `Analysis.PositionStore` | Append-only positions, distributed via `Horde.Registry` (`Analysis.PositionStoreRegistry`). Returns a `position_id` per `append/1`. |
| `Analysis.PositionDatabase` | Underlying storage for `PositionStore`. Disk-backed (DETS segments) when configured. Property indexes (`open_files`, `material`) for query. |
| `Analysis.Rooms` | Room registry. `start_room / get / add_analysis / remove_analysis / stop_room`. Each Room is a `RoomServer` GenServer under `Horde.DynamicSupervisor`. |
| `Analysis.Room` | Just `id` + `analysis_ids`. The list of analysis IDs in this Room. |
| `Analysis.RoomServer` | GenServer holding the Room state. Subscribed to via `RoomEvents`. |
| `Analysis.AnalysisEvents` | `:pg` based — when an analysis is updated, all subscribed processes receive `{:analysis_changed, analysis_id}`. (Not yet Phoenix.PubSub — see migration notes.) |
| `Analysis.RoomEvents` | Same pattern, for Room updates. |

### `apps/web` — what we'd replace

| File | Purpose |
|---|---|
| `Web.Router` | Three routes: `/` (PageLive, static-ish home), `/analyses` (AnalysesLive, lists all analyses + create), `/rooms/:room_id` (RoomLive, the workspace). Browser pipeline runs `Localize.Plug.PutLocale` from query/session/accept-language. API pipeline only has `/health` and `/ready`. |
| `Web.RoomLive` | The big one. ~940 lines. Manages the Room: subscribes to `RoomEvents` and `AnalysisEvents`, dispatches all `play_move / edit_position / promote / remove_subtree / set_comment / create_analysis / add_analysis / remove_analysis / select_analysis / navigate_*` events, reconciles the current `path` when an analysis changes elsewhere, renders the move tree, board, position editor, comment form. Uses HEEx components (`Web.Components.ChessBoard`, `Web.Components.MoveTree`, `Web.Components.PositionEditor`). |
| `Web.AnalysesLive` | Lists `Analyses.list()` + "open analysis" handler that calls `Rooms.start_room` and `Rooms.add_analysis`. |
| `Web.Components.ChessBoard` | HEEx board component for the LiveView. |
| `Web.Components.MoveTree` | HEEx move tree. |
| `Web.Components.PositionEditor` | HEEx position editor. |
| `Web.Endpoint` | Standard Phoenix endpoint. Serves static from `priv/static`. LiveView socket at `/live`. |
| `Web.Application` | Just Phoenix.PubSub + Endpoint. No Analysis supervision — that's in `Analysis.Application`. |

## Wire format gap

The prototype's wire format:

```json
// POST /api/move
{
  "position": {
    "pieces": [[0, "white_rook"], ...],
    "side_to_move": "white",
    "castling_rights": ["white_kingside", ...],
    "en_passant": null
  },
  "move": { "from": 12, "to": 28, "promotion": null }
}
```

The real backend expects:

```json
// POST /api/analyses/:id/move
{
  "analysis_id": "abc",
  "path": [0, 1],
  "move": { "from": 12, "to": 28, "promotion": null }
}
```

— and returns the updated analysis document plus the new path:

```json
{
  "analysis": { ...Analysis.Analysis.t()... },
  "revision": 7,
  "new_path": [0, 1, 0]
}
```

The SPA doesn't store positions itself; the backend's `PositionStore`
owns them. The SPA gets positions back only for rendering (the current
board, the move tree labels). This is more efficient than sending full
positions every time.

## Data model alignment

The prototype's data model maps cleanly onto `apps/analysis`'s:

| Prototype | Real |
|---|---|
| `OccurrenceId` (string) | `Analysis.Analysis.path()` (list of integers) |
| `nodes: Map<OccurrenceId, Node>` | `Analysis.Analysis.root: Node.t()` (nested) |
| `Node { id, position, parentId, move, children, comment }` | `Analysis.Node { position_id, transition, comment, children }` |
| `Analysis { rootId, nodes, rootSideToMove }` | `Analysis.Analysis { id, root, start, source_game_id, metadata }` |
| `AnalysisStore.addMove(parentId, move)` | `Analysis.Analyses.play(analysis_id, path, move)` |
| `AnalysisStore.setComment(id, text)` | `Analysis.Analyses.set_comment(analysis_id, path, text)` |
| `AnalysisStore.removeSubtree(id)` | `Analysis.Analyses.remove(analysis_id, path)` |
| `AnalysisStore.promoteToMain(id)` | `Analysis.Analyses.promote(analysis_id, path)` |
| Local move replay via chess.js | Server-side via `Position.apply_move` (the backend already has this) |

The **only real shape change** is `OccurrenceId` → `path`. The rest of
the prototype code can be ported with minimal changes — rename
`OccurrenceId` to `Path`, replace the `Map<OccurrenceId, Node>`
indexing with tree-walking via `Node.at(root, path)`.

## What's missing from the prototype

| Surface | Backend needed |
|---|---|
| Real Rooms (currently a local code) | `POST /api/rooms`, `POST /api/rooms/:code/join` |
| Real persistence | `Analysis.Analyses` API (already exists) + SPA stores revision |
| Move persistence | `POST /api/analyses/:id/move` (the SPA calls `Analyses.play/3`) |
| Comments persistence | `PUT /api/analyses/:id/comments/:path` (`Analyses.set_comment/3`) |
| Promotion / removal | `POST /api/analyses/:id/promote`, `POST /api/analyses/:id/remove` |
| Position editor | `POST /api/analyses/:id/edit` (`Analyses.edit/3`) |
| PGN import | `POST /api/import/pgn` (uses `Analyses.create_from_game/2`) |
| Lichess import | OAuth + `GET /api/import/lichess/:study_id` |
| Chess.com import | `GET /api/import/chesscom/:username` |
| Search | `GET /api/search/games?...` (search index doesn't exist yet) |
| Engine | Phoenix Channel `engine:<analysis_id>` (engine infra not yet built) |
| Real-time updates | Phoenix Channel `room:<room_id>` + `analysis:<id>` (PubSub) |
| Auth | AuthN/AuthZ on every endpoint |
| Multi-user via Channels | Phoenix PubSub + Channels (currently `:pg`-based) |

## Component-by-component migration

| Prototype component | Real implementation changes |
|---|---|
| `Layout.tsx` | Port as-is. Theme + locale persistence works. |
| `Board.tsx` | Read position from `Analysis.Analysis` (via path). Optimistic local update before server reply, snap-back on `{:error, :illegal_move}` or `{:error, :conflict}`. Track revision. |
| `MoveTree.tsx` | Replace `OccurrenceId` with `path`. Use `Analysis.Analysis` shape directly. |
| `CommentPane.tsx` | Read/write via `Analyses.set_comment` (no more localStorage). |
| `EnginePanel.tsx` | Keep demo engine. Swap `engineStore.start()` to a real Worker for Stockfish.wasm in the same shape. |
| `analysesStore.ts` | Replace with real API calls: `GET /api/analyses`, `POST /api/analyses`, `GET /api/analyses/:id`. Track revision per loaded analysis. |
| `Library.tsx` | Read from API. "Open" navigates to workspace with that analysis loaded. |
| `Research.tsx` | Stub — search backend doesn't exist yet. Render the UI with explicit "search not wired" empty state. |
| `Import.tsx` | PGN parsing stays client-side (chess.js). Submit to `POST /api/import/pgn`. Remove the demo auto-create. |
| `Home.tsx` | `POST /api/rooms` (create) or `POST /api/rooms/:code/join` (join). |
| `Room.tsx` | Wire to real `Rooms` API. Subscribe to `RoomEvents` for live updates. |

## Proposed migration plan

### Phase 1 — SPA skeleton inside `apps/web`

- Add `apps/web/assets/` with the SolidJS client (Vite-built bundle).
- Configure `Web.Endpoint` to serve the bundle at `/`.
- Configure `Web.Endpoint` to serve a JSON API for the existing routes.
- Replace `PageLive` (`/`) with a tiny SPA that calls `GET /api/health` to prove wiring.
- Keep `Phoenix.PubSub` for events (or wire it now; current app uses `:pg`).

### Phase 2 — Port the Room workspace

- Replace `Web.RoomLive` with the SPA's `AnalysisWorkspace` mounted over the Room shell.
- The SPA calls `Analyses.get / play / edit / promote / remove / set_comment`.
- Real-time updates come from a Phoenix Channel (`room:<room_id>`) broadcasting `analysis_changed` events.
- `Localize.Plug.PutLocale` already runs in the browser pipeline; the SPA reads `window.__LOCALE__` or a meta tag.

### Phase 3 — Library, Research, Import

- Library: wire to `GET /api/analyses`, `POST /api/analyses`.
- Research: stub with honest empty state (no search backend yet).
- Import: wire PGN import to `POST /api/import/pgn`. Defer Lichess / Chess.com.

### Phase 4 — Engine and real-time

- Engine: replace demo pseudo-engine with Stockfish.wasm worker.
- Server-side engine: Phoenix Channel `engine:<analysis_id>` for streaming eval.
- AuthN/AuthZ: add `Web.Auth` plug pipeline; gate mutations behind a session.

### Phase 5 — Polish

- Position editor (already partly in HEEx; port and integrate).
- Annotations (arrows, colored squares, occurrence-scoped).
- Responsive / touch / keyboard audit.
- Settings modal (theme, locale, future preferences).
- Self-host OpenSans (replace Google Fonts CDN with bundled woff2).
- Vite plugin for Phoenix lifecycle in dev (keep stdin open, exit on Phoenix close).

## Decisions on the open questions

1. **Channels vs PubSub** — Migrate `:pg` → Phoenix.PubSub + Channels in
   `apps/analysis`. The analysis events today broadcast on a single
   `:pg` group; Phoenix.PubSub gives us the same shape with
   distribution guarantees. Channels on top (`room:<room_id>`,
   `analysis:<analysis_id>`) for the real-time UX.

2. **Position caching** — Cache client-side. The board reads positions
   from a small local store keyed by `position_id`. On `play_move`, the
   SPA optimistically updates the local cache; on server reply it
   either confirms or rolls back. Same pattern for comments and
   annotations.

3. **Revision model** — Optimistic concurrency on **every** write
   (`play`, `edit`, `set_comment`, `promote`, `remove`). The SPA tracks
   one revision per loaded analysis. On `{:error, :conflict}`, refetch
   the analysis, merge, and retry once before surfacing a "stale"
   error to the user.

4. **URL addressing** — Paths. `?path=0,1,2` in URLs. The prototype's
   `OccurrenceId` is dropped in favour of `apps/analysis`'s path
   representation.

5. **GameStart** — Respect it. `Analysis.Analysis.start` is a
   `GameStart` (`:standard` / `:from_fen` / etc.). The SPA reads
   `start` when loading an analysis and shows the correct initial
   position; for `:from_fen` the FEN is part of the analysis
   metadata.

## What this means for the prototype

The prototype at `/tmp/opencode/prototype/` should keep working in
isolation. Its `localStorage`-backed `analysesStore` and fixture-backed
search are honest about being client-only. As we port surfaces to the
real implementation, we either:

- **Adapt**: change the prototype's components to consume the real API
  instead of the local store (preferred — keeps the prototype as a
  visual reference for the real impl).
- **Replace**: delete the prototype surface once the real one lands.

The `analysesStore` (localStorage) was useful as a prototype-only
facility. The real impl will not use it.
