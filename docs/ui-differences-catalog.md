# UI difference catalog — reference vs rebuild

Reference: **https://blunderfest.org/#/r/t8ymh** (React SPA, source `/home/jeroen/blunderfest`) — "Ref" below.
Rebuild: **http://localhost:4000/rooms/UYV644** (Phoenix LiveView, source `/home/jeroen/openchesslab`, branch `ui-rework`) — "New" below.

Captured 2026-09-28 by driving both apps side by side (screenshots in `.playwright-mcp/ui-diff/`), plus a source read of both frontends.

**Context that matters for the decisions**

- The rebuild's backend is WIP. Several surfaces are explicitly stubbed with a `DEMO` badge (engine, search, import providers, library). Those show up below as missing; that is expected, not a surprise.
- The reference app was recently rebranded to OpenChessLab; both apps share the same name, logo, colours, fonts and the `#ebecd0 / #779556` board palette.
- Types: **L&F** = look & feel · **UI** = structure/placement · **UX** = interaction/behaviour · **MISS** = in reference, absent in rebuild · **NEW** = in rebuild, absent in reference · **BUG** = defect observed.
- Decision labels: **keep** = no change needed · **backlog** = implement · **defer** = revisit when the backend feature lands · **skip** = won't do · **☐** = still open.

Evidence by area: `old-room-01.png` / `new-room-populated.png` (room), `old-home.png` / `new-home-01.png` (home), `old-import.png` / `new-room-debug.png` (import), `old-search`-less vs `new-search.png`, `old-mobile-room.png` / `new-mobile-room.png`, `old-review-*.png`, `old-chart-*.png`, `old-evidence.png`, `old-comment.png`, `old-shortcuts.png` / `new-shortcuts.png`, `old-tour`-less vs `new-tour.png`, `old-notfound.png` / `new-notfound.png`.

---

## A. Global chrome & navigation

**GL-01 · Header composition** (UI)
Ref: logo + room chrome (code chip, presence, region chip) + help + theme + account name.
New: logo + app settings (search, piece set, theme, EN/NL, tour, shortcuts); no account.
Decision: **keep**

**GL-02 · Room code chip placement** (UI)
Ref: mono code chip in the header, click-to-copy, morphs to "Copied!" with live-region announcement.
New: `Room UYV644` heading + copy icon in the left sidebar; feedback via toast.
Decision: **keep**

**GL-03 · Presence placement** (UI)
Ref: overlapping avatars in the header, click opens a members popover (roles, follow/present, promote/demote).
New: avatar row in the sidebar room header; clicking another viewer jumps to their analysis/position (`follow-viewer`); no popover, no roles.
Decision: **keep**

**GL-04 · Connection / region chip** (L&F/UI)
Ref: header chip with country flag, ping, tooltip "Connected to X; room stored in Y; N ms round trip".
New: sidebar line with `⌂`/region badge, `— ms` then measured ping, same tooltip idea.
Decision: **keep**

**GL-05 · Accounts / identity** (MISS)
Ref: anonymous fun name in the header, account menu with Lichess OAuth sign-in/out; "You are {name} · anonymous" on home.
New: no accounts anywhere; participants show initials only (no display name in the room chrome).
Decision: **defer** — revisit when the backend feature lands

**GL-06 · Update banner** (MISS)
Ref: polls `/version.json` every 60 s and offers "A new version … available / Reload".
New: none.
Decision: **backlog**

**GL-07 · Service status** (MISS)
Ref: home footer shows "Connecting to analysis service… / online / unreachable" + region.
New: `/health` + `/ready` exist but nothing surfaces them in the UI.
Decision: **skip**

**GL-08 · Theme control** (L&F)
Ref: one 28 px button that cycles system → light → dark, title shows current.
New: 3-button segmented group (system / light / dark).
Decision: **keep**

**GL-09 · Language toggle** (NEW)
Ref: English only (one locale registered).
New: `EN`/`NL` toggle, full Dutch catalog (incl. localised SAN `Pf3`, `D`, `T`, `L`).
Decision: **keep**

**GL-10 · Piece sets** (NEW/L&F)
Ref: cburnett only, no picker.
New: Merida (default) + Cburnett selectable in the header, persisted.
Decision: **keep**

**GL-11 · Help vs separate buttons** (UI)
Ref: "?" help menu with tour + keyboard shortcuts.
New: separate tour flag and "?" buttons in the header (no menu).
Decision: **keep**

**GL-12 · Routes & codes** (UI/UX)
Ref: hash route `#/r/CODE`; 5-char lowercase-safe codes (no `i l o 0 1`).
New: path route `/rooms/CODE`; 6-char uppercase codes (`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`).
Decision: **keep**

**GL-13 · Page titles** (L&F)
Ref: "OpenChessLab" (always).
New: "OpenChessLab" on home, "Room CODE" in a room.
Decision: **keep**

---

## B. Home & room entry

**HM-01 · Hero copy** (L&F)
Ref: "OpenChessLab / Explore chess. Understand more."
New: "OpenChessLab / Analyse games and positions together in a shared room."
Decision: **keep**

**HM-02 · Create card** (L&F)
Ref: "Start a study" — "Creates a room, makes you the owner, hands you a code to share." / "Create a room" / "No account needed."
New: "Create a room" — "Get a short code you can share. Anyone with the code can join." / "Create Room" / "No account needed."
Decision: **keep**

**HM-03 · Join card** (L&F/UX)
Ref: "Join with a code" — "Someone shared five characters? Drop them in."; 5-char input, lowercase.
New: "Join a room" — "Enter the code someone shared with you."; 6-char input, uppercase.
Decision: **keep**

**HM-04 · Device library on home** (MISS)
Ref: "Your games" panel (from `/api/library`); clicking a game creates a new room seeded with it; per-row remove.
New: none on home; the library is a demo tab inside the import dialog.
Decision: **defer** — revisit when the backend feature lands

**HM-05 · Demo room link** (MISS)
Ref: "Peek at the demo room →" joins hard-coded read-only room `#/r/chess`.
New: none; no read-only/demo mode at all.
Decision: **defer** — revisit when the backend feature lands

**HM-06 · Home footer identity/status** (MISS)
Ref: "You are Lively Zebra 62 · anonymous · Analysis service online · Connected to 🇳🇱 Amsterdam".
New: none.
Decision: **skip**

**HM-07 · Create/join errors** (UX)
Ref: rate-limit message ("Too many rooms created just now. Try again in a minute."), "Enter a room code".
New: "Could not create a room: …", "No room with that code. Check the code and try again."; no rate-limit copy.
Decision: **keep**

---

## C. Room shell, rail, sidebars

**RM-01 · Left rail content** (UI/UX)
Ref: "BOARDS · N" games rail: title (renameable), presenter badge, opening/ECO, result chip, hover ✕ remove.
New: "ANALYSES · N" list: "Analysis N" / "Game id", "standard start · rev N", other-viewer count, active state.
Decision: **keep**

**RM-02 · Rail actions** (UI)
Ref: import (upload icon) + "New game" (+) that creates "Game N" from the initial position.
New: import + "New analysis" (+), "Set up a position…" text button (opens the setup modal).
Decision: **keep**

**RM-03 · Analysis management** (MISS/UX)
Ref: inline rename (double-click title, Enter/Esc), immediate remove, custom titles.
New: no rename, no remove, no reorder; labels are automatic.
Decision: **backlog** — remove first (backend exists), then rename

**RM-04 · Chat placement** (UI)
Ref: "CHAT" tab in the right dock.
New: "Room chat" at the bottom of the left sidebar; messages show "viewing {analysis}".
Decision: **keep**

**RM-04a · Chat unread badge** (UX)
Ref: unread badge (9+ cap), own messages never count, cleared on opening the tab.
New: no unread indicator.
Decision: **backlog** — low priority

**RM-04b · Chat moderation & role gating** (MISS)
Ref: owner-only message delete; viewers get "Only the owner and collaborators can chat."
New: anyone can post; no delete.
Decision: **defer** — needs roles (RM-08)

**RM-05 · Right dock tabs** (MISS/UI)
Ref: MOVES · REVIEW · CHAT tabs (WAI-ARIA tablist, panels stay mounted).
New: single "MOVES" panel with a "Share" menu; no tabs.
Decision: **keep**

**RM-06 · Empty-room states** (L&F)
Ref: "Empty room" CTA ("Import games from PGN or Lichess, or start from the initial position and just play.") with "Import games" / "Fresh board"; viewers see "Nothing to analyse yet" + "listening for updates".
New: "Start an analysis" card with "Start an analysis" / "Import games"; one state for everyone.
Decision: **keep**

**RM-07 · Room-not-found state** (L&F/UX)
Ref: dedicated card with warning icon, explanation of 5-char codes/expiry, the code in mono, "Back to home".
New: single line "Failed to load room: …" + home link.
Decision: **backlog** — low priority polish

**RM-08 · Roles & presenter model** (MISS)
Ref: Owner / Collaborator / Viewer, presenter handoff, follow presenter, "Presenting" chips, permission gating (viewers can't play/chat/import).
New: flat participants; only follow-viewer; no permissions enforced in the UI.
Decision: **defer** — revisit when the backend feature lands

**RM-09 · Analysis loading/conflict states** (UX)
Ref: optimistic ops with seq replay; viewer state visible; no explicit conflict UI either.
New: revision-based server round trips; `room.someoneUpdated`, `room.loadingAnalysis`, `room.creatingAnalysis` keys exist but unused.
Decision: **defer** — revisit when the backend feature lands

---

## D. Board & board interactions

**BD-01 · Last-move highlight** (L&F/UX)
Ref: from/to squares highlighted after every move.
New: none (only selected / check / legal-target / insight layers).
Decision: **backlog** — top of the list (no backend work)

**BD-02 · Side-to-move indicator** (UI)
Ref: "WHITE/BLACK TO MOVE" chip above the board + 1 px colour strip on the mover's board edge.
New: "Side to move: White" text below the board (plus check/checkmate pill).
Decision: **keep**

**BD-03 · Players + result above the board** (MISS)
Ref: "? – ?" players and result `*` above the board.
New: none — PGN headers are parsed but dropped (`create_imported_analysis` does not store them).
Decision: **backlog** — keep headers as analysis metadata at import, then render them

**BD-03a · Opening / ECO name** (MISS)
Ref: "D02 · Queen's Pawn Game: Anti-Torre", follows the viewed line via a local openings book.
New: no opening book in this repo.
Decision: **defer** — needs book data

**BD-04 · Export / share actions** (UI/UX)
Ref: "PGN" downloads an annotated `.pgn` (variations, comments, NAGs, clocks, setup nodes split out) + "Save" bookmark to library.
New: "Share" menu: "Copy PGN" (mainline SAN only), "Copy FEN", "Export position image" (SVG), "Share · URL".
Decision: **backlog** — annotated PGN export; also fix "Export position image" to use the selected piece set

**BD-05 · Eval bar** (MISS/L&F)
Ref: vertical bar left of the board when the engine is on; animated sweep while thinking; eval pill; rich aria ("White is better by 1.30 pawns").
New: demo bar when the engine toggle is on, basic aria ("Demo evaluation bar …").
Decision: **defer** — revisit when the backend feature lands

**BD-06 · Check indication** (L&F)
Ref: radial red glow under the checked king.
New: red overlay on the king square.
Decision: **keep**

**BD-07 · Annotation colours** (L&F/UX)
Ref: 4 colours — Blue, Green, Purple, Red — keyboard `1`–`4`.
New: 5 colours — Yellow, Blue, Red, Orange, Purple — keyboard `1`–`5`, default blue.
Decision: **keep**

**BD-08 · Position editor** (UI/UX)
Ref: inline edit mode (palette strips top/bottom, eraser, turn toggle, "Clear board", "Reset position", "Done"/"Cancel"); chess-rule validation deliberately skipped; engine pauses.
New: side panel ("Edit mode" toggle, 12-piece palette + remove, side-to-move, castling rights, en passant, draft "Apply"/"Discard" with validation reasons) + separate "Set up a position" modal for new analyses; server validates.
Decision: **keep**

**BD-09 · Promotion** (UX)
Ref: no picker — automatically plays the first legal variant (chess.js order → knight first).
New: explicit "Choose a piece for the promoted pawn." modal in the current piece set.
Decision: **keep**

**BD-10 · Pass move (null move)** (MISS/UX)
Ref: dropping/tapping a move out of turn inserts a `--` pass node first, so you can play "1. e4 c5 -- a6" in one gesture.
New: none.
Decision: **defer** — needs null-move support in the analysis domain; skip if unused

**BD-11 · Drag-blunder flag** (MISS)
Ref: while dragging, a second engine instance evaluates the candidate and shows `??` / `?` / `?!` on the target square.
New: none.
Decision: **defer** — revisit when the backend feature lands

**BD-12 · Engine hint arrow** (MISS)
Ref: translucent arrow for the engine's best move (toggle "Hint arrows").
New: none.
Decision: **defer** — revisit when the backend feature lands

**BD-13 · Keyboard map** (UX)
Ref: ←/→ prev/next, Home/End first/last, `f` flip, `c` note (editors), square-focus arrows, `h`, `a a`, `1`–`4`, Esc.
New: `B` focus board, `M` move tree, `F` flip, `E` engine, `Home`/`End`, `1`–`5`, `?`, Esc; square-focus arrows, `H`, `A`, Enter; move-tree ←/→/↑/↓.
Decision: **backlog** — add global ←/→ prev/next; keep the rest

**BD-14 · Loop-of-keyboard/echo state** (L&F)
Both show the board cursor / legal move dots / drag ghost; New adds insight layers (open files, attacked squares, king zone, outposts) toggled from the position strip.
Decision: **keep**

---

## E. Move list, comments, PGN

**ML-01 · Move-list metadata** (MISS)
Ref: per move: NAG glyph, analysis mark (`??`/`?`/`?!` with "best …" tooltip), eval text (`+0.4`, `M3`), blue comment dot, book-exit glyph.
New: NAG glyph and inline comment only; no analysis marks, eval text, comment dot or book glyph.
Decision: **defer** — ships with the game-review milestone (RV)

**ML-02 · Off-mainline breadcrumb** (MISS)
Ref: "… 8. Nc4 dxc4 9. fxe4" above the list, click returns to the mainline.
New: none.
Decision: **backlog**

**ML-03 · Comment editing** (UI/UX)
Ref: modal popup with 6 quality NAGs, textarea, "Unsaved · ⌘↵ to save", "Clear", Cmd/Ctrl+Enter saves.
New: inline panel section with NAG buttons, textarea "Comment for this occurrence (empty to clear)", "Save comment" button (toast on save).
Decision: **keep** — optional later: Cmd/Ctrl+Enter to save

**ML-04 · Variation actions** (NEW)
Ref: protocol exists but no promote/delete UI.
New: "Promote variation" and "Remove subtree" buttons when not at root.
Decision: **keep**

**ML-05 · Move-list keyboard** (UX)
Ref: roving listbox, ↑/↓ focus, Enter/Space select; auto-scroll.
New: roving listbox, ← parent / → first child / ↑ previous sibling / ↓ next sibling, always-shown hint line.
Decision: **keep**

**ML-06 · Comment-on-move entry point** (UI)
Ref: ghost button "💬 Comment on this move" under the board, plus toolbar 💬, plus `c`.
New: comment section in the right panel only.
Decision: **backlog** — low priority

---

## F. Engine

**EN-01 · Real engine** (MISS)
Ref: in-browser Stockfish 18 Lite single-thread WASM, ~250 ms movetime, MultiPV 1–3.
New: `DemoData.engine_preview` fixture, "Illustrative fixture only — this is not a chess engine." + "No engine connected yet — no evaluation."
Decision: **defer** — schedule the provider spike (in-browser WASM vs server-side)

**EN-02 · Engine controls** (MISS/UI)
Ref: status dot (off/thinking/ready/error), "Depth n", MultiPV select, hint-arrows toggle, on/off switch, retry, WDL bar, PV rows clickable to insert as a variation, "Analyze line" button.
New: settings popover (provider/depth/movetime/multipv, disabled) + on/off switch; demo stats (Eval/Depth/Nodes/NPS) and 3 PV rows.
Decision: **defer** — follows EN-01

**EN-03 · Engine/board coupling** (UX)
Ref: engine pauses in edit mode ("Engine paused while editing — Done resumes it.").
New: no coupling; demo engine is independent of edit mode.
Decision: **defer** — follows EN-01

---

## G. Review / game report

**RV-01 · REVIEW tab** (MISS)
Ref: right-dock "REVIEW" tab with nested MOMENTS · REPORT · GAME INFO.
New: absent.
Decision: **defer** — part of the engine-gated game-review milestone

**RV-02 · Analyze game job** (MISS)
Ref: whole-game engine run ("Analyze game" / "Re-analyze", progress "Analyzing N/M…", help popover); powers eval marks, Moments and the report.
New: absent.
Decision: **defer** — enabler for RV-01/03/04; client vs server decided in the engine spike

**RV-03 · Moments** (MISS)
Ref: five biggest eval swings with mini boards, "eval before → after", "best {move}", empty states.
New: absent.
Decision: **defer** — follows RV-02

**RV-04 · Report & Game info** (MISS)
Ref: accuracy %, `?? / ? / ?!` counts per side, per-move mark rows; Game info: Event/Date/Result/Mainline plies/Total nodes.
New: absent.
Decision: **defer** — Game info folds into BD-03; Report follows RV-02

---

## H. Positional context & historical evidence

**HE-01 · POSITIONAL CONTEXT panel** (MISS)
Ref: corpus continuations for the cursor FEN (SAN, opening name, game counts, W/D/B bar), hover preview arrow, click plays for the room; transpositions; "Endgame/tablebase territory" notes.
New: absent (no corpus wiring in the room).
Decision: **skip for now** — corpus is not on the rebuild roadmap yet

**HE-02 · Historical evidence dialog** (MISS)
Ref: "Find examples" → dialog with decision menu, relevant-game list, mini board, facts card (Position/Route/Continuation/Historical evidence), "Add as variation" / "Add to room".
New: absent.
Decision: **defer** — revisit if/when the corpus comes over

**HE-03 · Position name / book** (MISS)
Ref: ECO · name when the book labels the cursor position; outside-book note.
New: absent.
Decision: **defer** — optional static openings book later

---

## I. Bottom strip

**TL-01 · Game-flow charts** (MISS)
Ref: tabs EVAL · MATERIAL · ACTIVITY · THINK TIME · TIME LEFT — per-ply charts with scrub-to-navigate, book/endgame shading, capture markers, `??/?/?!` dots, cp/% toggle, quality strip, per-layer empty states.
New: absent.
Decision: **backlog** — medium priority; sequence: MATERIAL/ACTIVITY (engine-free) → EVAL with RV-02 → clocks with TL-04

**TL-02 · Position insights instead** (NEW)
New: "Material / Space / Layers" tabs — material totals, controlled-square counts, and board overlay checkboxes (Open files, Attacked squares, King zone, Outposts); collapsible, persisted.
Ref: nothing equivalent.
Decision: **keep**

**TL-03 · Analyze-game entry point** (MISS)
Ref: "Analyze game"/"Re-analyze" button + progress + "?" help popover in the strip header.
New: absent.
Decision: **defer** — follows RV-02

**TL-04 · Clock data** (MISS)
Ref: Think time / Time left use `[%clk]` + TimeControl from imported games.
New: no clock parsing or display.
Decision: **defer** — needs clock parsing in the importer

---

## J. Import, library, accounts

**IM-01 · Import layout** (L&F/UI)
Ref: source rail on the left (Paste / Lichess / Chess.com), content right, fixed checkout bar at the bottom ("Nothing selected yet" / "N games · N ply · PGN", "Imports are shared with everyone in the room. Esc to cancel", "Options", primary "Import").
New: horizontal tabs on top (Paste / My library / Lichess / Chess.com), content above a footer with "Use sample" / "Save to library" / "Import".
Decision: **keep**

**IM-02 · Import sources** (MISS)
Ref: Paste accepts multiple PGNs + Lichess URLs with a live parsed tray; Lichess by URL/ID plus linked-account recent games/studies; Chess.com by username/month.
New: Paste demo (single game, main line only, comments/variations ignored); "My library" demo; Lichess/Chess.com show fixture rows ("Show demo games").
Decision: **defer** — with the import-provider milestone

**IM-03 · Import options** (MISS)
Ref: "Options" popover with "Keep in the import": Comments / Variations / Names & event / Engine annotations.
New: none (translated keys exist but unused).
Decision: **defer** — follows IM-02

**IM-04 · Multi-game selection & per-game errors** (MISS/UX)
Ref: tray with checkboxes, per-row parse failures, partial failures abort the whole import.
New: one textarea → one game.
Decision: **defer** — follows IM-02

**IM-05 · Import form is currently broken** (BUG)
Repro: open Import → paste any PGN or click "Use sample" → Import. Result: "Parse error: No moves found" and no analysis.
Cause observed: the LiveView form submits `value: ""` when the `live_file_input` is present; removing the file input from the DOM makes the same submit work ("Imported 1 game into this room."). Worth fixing independently of the backend work.
Decision: **backlog** — high priority (bug fix, backend-independent)

**IM-06 · Library** (MISS/UI)
Ref: device library endpoint + home "Your games" + board "Save" bookmark with saved/remove states.
New: demo "My library" tab in the import dialog + "Save to library"; `local-*` entries only.
Decision: **defer** — revisit placement together with HM-04

**IM-07 · Lichess account linking** (MISS)
Ref: OAuth link from the account menu and from import; returns to the room.
New: none.
Decision: **defer** — ties to GL-05 (auth)

---

## K. Chat & presence

**CH-01 · Chat placement, badge, moderation** — see RM-04 / RM-04a / RM-04b (decisions recorded there).

**CH-02 · Message context** (NEW)
New: each message shows "viewing {analysis}" (plus ply count) when sent while viewing a position.
Ref: none.
Decision: **keep**

**CH-03 · Follow-viewer** (NEW/UX)
New: click a viewer avatar to jump to their analysis and path.
Ref: has "follow presenter" instead; no per-viewer follow for non-presenters.
Decision: **keep**

**CH-04 · Chat history model** (backend)
Ref: op-log-backed history per room; New: in-memory, max 200 messages, reset on reload. Note only — likely backend scope.
Decision: **defer** — backend scope

---

## L. Search

**SE-01 · Search modal** (NEW)
New: "Search games & positions" modal with Player/Colour/Result/Opening/date filters + Position (FEN, match mode, substitutions), demo fixtures, result rows that can be opened as analyses.
Ref: no search UI (roadmap only).
Decision: **keep** — revisit the wiring with the backend

---

## M. Tour, shortcuts, dialogs

**DG-01 · Tour style** (L&F/UX)
Ref: spotlight overlay anchored to board/rail/sidebar/timeline/code/members/help, 7 steps, ←/→ + Esc.
New: modal carousel with 7 text steps, Skip/Back/Next/Done.
Decision: **backlog** — upgrade to a spotlight/anchored tour

**DG-02 · Shortcuts dialog content** (UX)
Ref: 2 sections (prev/next, first/last, flip, note; square cursor, select/play, highlight, arrow, colours, cancel).
New: adds `?`, `Esc`, `B`, `M`, `E`, move-tree arrows; no prev/next or note shortcut.
Decision: **keep**

**DG-03 · Modal backdrop** (L&F)
Ref: dark overlay `bg-void/75` + blur.
New: transparent backdrop with blur/saturate only.
Decision: **keep**

**DG-04 · Reusable help popovers** (MISS)
Ref: "?" popovers for "About Analyze game" and "Historical examples, explained".
New: none (features absent).
Decision: **defer**

---

## N. Feedback, errors, loading

**FB-01 · Toasts** (NEW)
New: bottom-right info/error toasts (copy, save, import, promote/remove, illegal move) with close.
Ref: no toast system; inline transient labels ("Saved ✓", "Copied!", "Couldn't save") + update banner.
Decision: **keep**

**FB-02 · Connecting state** (UX)
Ref: "Connecting..." with pulsing dot while joining; then content or the not-found card.
New: content or error line; no connecting state.
Decision: **skip**

**FB-03 · Loading placeholders** (MISS/L&F)
Ref: skeleton/pulse bars, eval-bar thinking sweep, "Analyzing N/M…", "Loading corpus statistics…", etc.
New: none (no skeletons/spinners); `room.loadingAnalysis`/`room.creatingAnalysis` unused.
Decision: **skip for now** — revisit if analysis loading ever feels slow

**FB-04 · Conflict / someone-updated UI** (MISS)
Ref: none either (ops replay silently).
New: keys exist (`room.someoneUpdated`) but unused; revisions are server-side.
Decision: **defer** — with RM-09

---

## O. Settings, theming, i18n

**ST-01 · Preferences** (UI)
Ref: theme cycling, engine on/off + hints + lines, eval scale, timeline layer, Chess.com username, device id (all `blunderfest.*`).
New: theme, locale, piece set, annotation colour, edit mode, strip open/tab (all `openchesslab:*`).
Decision: **keep**

**ST-02 · i18n coverage** (NEW)
New: 371 keys × en/nl; Ref: en only. Existing untranslated/new keys (import options, engine telemetry, shared library) hint at planned UI.
Decision: **keep**

---

## P. Responsive & touch

**MO-01 · Stack order on small screens** (UI)
Ref: header keeps room chrome; games rail becomes a horizontal strip; board; timeline; then MOVES/REVIEW/CHAT panel.
New: sidebar first (room + analyses + chat), then board, then position strip, then MOVES panel.
Decision: **keep**

**MO-02 · Settings access on mobile** (UI)
Ref: help + theme stay in the header; account name hides < md.
New: gear `<details>` popover holding piece set + theme + tour; search/language/shortcuts remain.
Decision: **keep**

**MO-03 · Touch gestures** (UX) — both support drag & drop, long-press draw, and stack instead of drawers. Essentially at parity; listed for completeness.
Decision: **keep**

---

## Q. Cross-cutting

**XX-01 · Brand & domain** (intentional)
Both apps are "OpenChessLab" with the same mark and colours; the deployment still lives at blunderfest.org. No action expected.
Decision: **keep** — intentional

**XX-02 · Demo stubs** (intentional for now)
New "DEMO" badges on Engine, My library, Lichess, Chess.com, Search. These are honest labels for WIP backend surfaces; the list above says what each will need.
Decision: **keep** — intentional

---

## Decided backlog (in suggested order)

**Progress 2026-09-28:** items 1 and 2 done (commit `8033d0c`).

1. **IM-05** fix: import form submits empty while the file input is present (backend-independent). — ✅ done
2. **BD-01** last-move highlight. — ✅ done
3. **RM-03** remove analysis (backend exists), then rename.
4. **BD-03** store PGN headers as analysis metadata + show players/result.
5. **BD-13** global ←/→ previous/next move.
6. **ML-02** off-mainline breadcrumb.
7. **BD-04** annotated PGN export; fix position-image export to use the selected piece set.
8. **TL-01** timeline charts, staged: MATERIAL/ACTIVITY (engine-free) → EVAL with RV-02 → clocks with TL-04.
9. **DG-01** spotlight/anchored tour.
10. **ML-06** "Comment on this move" entry point (low).
11. **RM-04a** chat unread badge (low).
12. **RM-07** room-not-found card polish (low).
13. **ML-03** Cmd/Ctrl+Enter to save a comment (optional micro).
14. **GL-06** update banner (when the deploy pipeline settles).

### Deferred until the backend/feature lands

- **Engine + game review**: EN-01/02/03, RV-01..04, ML-01, BD-05, BD-11, BD-12, TL-03, FB-04, RM-09.
- **Import, library, accounts**: IM-02/03/04/06/07, GL-05, TL-04, BD-03a.
- **Roles / presenter**: RM-04b, RM-08.
- **Corpus / historical evidence**: HE-02, HE-03, SE-01 wiring.
- **Misc**: BD-10 pass move, DG-04 help popovers.

### Skipped

- HE-01 (for now), GL-07 service status, HM-06 home footer, FB-02 connecting state, FB-03 loading placeholders.

Screenshots for every claim are in `/home/jeroen/openchesslab/.playwright-mcp/ui-diff/` (old-* = reference, new-* = rebuild).

## Post-catalog changes (2026-09-28)

Two issues reported after the walkthrough, both fixed:

- **Drag-and-drop flicker:** the dragged piece snapped back to its origin until the server replied. The drag ghost is now held on the target square until the `pushEvent` reply arrives (2.5 s fallback), so the piece never flashes back. Commit `d115396`.
- **Mobile room layout (revises MO-01):** below 860px the room now reads *room bar → single-row analysis chips (setup/import/new inline) → board → controls/position strip → moves panel*, and chat is a bottom sheet opened from the room bar (backdrop + Esc close it). Implemented with `display: contents` + `order`, so the desktop grid is unchanged. Commit `54270a4`; screenshots `mobile-final-top.png`, `mobile-v2-chat.png`.
- **Reported interaction bugs (all fixed in `aacb823`):**
  - Move tree: the first click was swallowed because a `phx-focus` round trip patched the button mid-click; the roving tabstop now lives client-side in the `MoveList` hook.
  - "Set up a position…" looked dead: the setup board rendered with `nil` insights and `white_outpost or black_outpost` raised `BadBooleanError`, crashing the LiveView on open.
  - Touch: added the 350 ms long-press gesture for arrows and square highlights (matching right-drag); a drag cancels the long press so piece moves still work. This is the touch counterpart of the old app's long-press drawing.
  - Position editor/setup palettes: capped at 15rem (~50 px pieces on phones instead of 78 px) and pieces can now be dragged from the palette onto the board.
  - Header: the keyboard-shortcuts button is hidden below 640px.
  - Copy: the two position flows are now distinguishable — "New analysis from a position…" (setup, creates a new analysis) vs "Edit this position" (editor, records an edit node in the current analysis).
- **Second mobile testing round (`4a6c552`):** move-tree actions moved above the commentary; the draft notice became a fixed bottom bar (no more layout shift, survives closing the editor); the "Edit mode" toggle was removed (opening the editor implies free editing); the editor's X now actually closes the panel; the tour supports ←/→ and suspends other shortcuts while open.
- **Mobile Option 1 implemented (`8d10b00`):** below 860px the room is a fixed-viewport shell — one-line room row, board sized to the remaining height (~338 px at 390×844), then Moves/Analyses/Chat tabs with an internally scrolling panel (30%, toggle to 40%). The analyses list and chat live in their tabs; the chat sheet is gone. The position strip expands upward as an overlay, and the position editor is a bottom sheet with palette drag. Tab/panel state is client-side on `<body>` (RoomTabs hook + localStorage); desktop is unchanged. The throwaway prototype was moved out of the repo to `/tmp/opencode/mobile-shell-prototype.html`.
- **Board keyboard polish (`1f5e21f`):** the focused square gets a 3 px inset focus ring (plus a dark inner edge) that can't be clipped; `A` starts *and finishes* an arrow (same square cancels), matching the old app; `Esc` cancels an in-progress arrow/drawing instead of clearing every annotation; an armed pill ("Arrow from e2 — …") and an amber anchor marker make the drafting state obvious; the shortcuts dialog documents both.
- **Style consistency (`6e1a945`):** all section labels (ENGINE, COMMENT, ROOM CHAT, POSITION EDITOR, ANALYSES, BOARD TOOLS, CASTLING RIGHTS, strip tabs) share the small-caps style; the arrow pill uses the highlight colour and the informational DEMO badges/notes are neutral, leaving warning amber for the unsaved-draft bar only.
- **Notices and move list (`94ff661`):** toasts auto-dismiss (info 4 s, errors 8 s) without a stale timer clearing a newer notice; the move list now starts at its full height (14 rem mobile, 38 vh desktop) instead of growing with the number of moves.
- **Arrow navigation (`55a9350`):** plain left/right step the mainline whenever the board or move tree is not focused; with the board focused they still move the square cursor, and Shift+left/right steps the mainline from there. Both variants are in the shortcuts dialog.
- **Chat auto-scroll (`4e910f5`):** the chat log now follows new messages reliably (stickiness tracked before the append), reveals the newest message when the hidden mobile Chat tab becomes visible, always follows your own message, and never yanks you while you are reading history.
- **Cross-region optimistic UI (`576be38`):** measured on production (ord client / ams room): annotation round trip ~265 ms, legal move round trip ~2.4 s. The client used to clear the pending piece after 2.5 s (racing the reply → visible snap-back and jump), drop arrow previews on release (gap until the shape returned) and show highlights only after the reply. Pending moves are now held until the server confirms (12 s safety net, re-applied after patches) for both drag and click-to-move, and arrows/highlights render optimistically until the server's own shape appears (`data-shape-key` matching; morph-reused nodes are kept).
- **Rapid moves under cross-region latency (2026-09-29, follow-up to `576be38`):** playing a *second* move while the first awaited its ~2.4 s round trip broke down: any piece click ran `clearDragPreview()`, which wiped the pending move's ghost and un-hid its source (the move looked like it snapped back), click-to-move was disabled entirely while a move was pending, and a second ghost reused the first move's piece. Server-side, the round trip itself was 9+N serialized cross-region calls (~230 ms each on the ord↔ams path: `Analyses.play` ×4, `Rooms.get` + `room_analyses` re-fetch ×2+, `current_position` + move-list positions ×N+1) plus a redundant full self-refresh after every move (`{:analysis_changed, ...}` re-fetching everything just rendered, blocking the next interaction ~1 s). Fixed on both sides: the change event now carries its revision so the LiveView skips its own writes; the sidebar revision is patched from the analysis already in hand; positions are cached per tree (pruned to the rendered analysis) and the move's result position is seeded from the validated move — a move ack is now exactly 4 cross-region calls (get analysis, get position, append position, update analysis) with no follow-up refresh. Client-side, pending moves are a per-move queue: each move gets its own ghost (with the piece it moved) and hides only its own source; click-to-move keeps a local selection (`data-spec-selected`, only while the board is in play mode via `data-play`) so target clicks play optimistically without waiting for the selection round trip; ghosts are confirmed when a patch puts the piece on the target, and roll back only once no other move is still in flight (hook pushes lock the board element for the event's duration, so intermediate board patches defer to the last reply). Verified with a 2400 ms simulated move path: a 6-click opening sequence enters in ~0.8 s, the board shows the speculative sequence immediately, and everything converges with no snap-backs, stuck ghosts or duplicate pieces; illegal moves roll back with the usual toast.
- **Merged square highlights (`7025a8b`):** same-colour square annotations now draw only the sides facing a non-highlighted neighbour, so adjacent squares form one coherent outline (rectangle, L-shape, 2×2 block) instead of stacked boxes with double borders. Diagonals and other colours never merge; orientation is respected; unit + LiveView tests cover it.
- **Board id collision + palette contrast (`58d841e`):** both boards rendered the same square ids (`square-e8`), and LiveView's keyed morphing falls back to element ids — adding the setup board consumed the room board's squares, so the board looked empty after closing the modal. Square ids are namespaced per board now, with a regression test. Piece palettes use the board-light background so both piece colours read in dark mode, and the "Import games" button matches the "New analysis" border.

Screenshots for every claim are in `/home/jeroen/openchesslab/.playwright-mcp/ui-diff/` (old-* = reference, new-* = rebuild).
