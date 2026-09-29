# Web

Phoenix LiveView serves the home page and collaborative room workspace. The
LiveView calls the existing `Analysis.Rooms` and `Analysis.Analyses` APIs
directly; chess legality, position validation and persistence remain owned by
the chess and analysis applications.

## UI architecture

The app now has one Phoenix-owned UI and no known non-browser clients. Keeping
the room/analysis JSON and Channel protocols would have duplicated the new
LiveView event path, so those SPA-only interfaces were retired. LiveView can
call the existing domain modules directly and use one connection for server
state, Presence, chat and analysis refreshes.

The board is the exception to server-owned interaction: pointer movement and
selection remain local in a small JS hook; only a completed move or annotation
is sent to the server. This avoids a round trip for every drag event while
keeping legality and persisted analysis state authoritative on the server.
The tradeoff is that completed analysis actions now wait for a LiveView update
rather than updating a React cache optimistically.

- `lib/web/live` contains the home and room LiveViews. Room changes are
  subscribed through the existing room/analysis event groups. `Web.Presence`
  and Phoenix PubSub carry participant state and ephemeral room chat.
- `lib/web/components` contains shared HEEx UI, including the board. The board
  remains server-rendered; `assets/js/app.js` uses a small LiveView hook for
  pointer gestures and drawing, sending only completed actions to the server.
- `assets/css/app.css` defines Tailwind's theme variables and base styles.
  Layouts and controls use Tailwind utilities in HEEx; custom CSS is limited to
  theme variables and board-specific details.
- `priv/i18n` contains the English and Dutch catalogs ported from the former
  browser UI. `Localize` continues to negotiate locale and keep it in session.

The previous React SPA was the only consumer of the room/analysis JSON API and
the `/socket` Phoenix Channels protocol, so those web-only routes and clients
have been removed. `/health` and `/ready` remain. No source in the chess,
position_db or analysis applications was changed.

## Demo-only features

The canonical game library/search and engine provider are not implemented in
the backend. The LiveView uses clearly labelled, in-memory demo fixtures for
search/provider flows and illustrative engine output. PGN import supports the
main line from the standard position and validates every SAN move with the
chess application. These fixtures are not presented as persisted games or real
engine calculations.

## Assets and checks

The web app uses Phoenix's Mix-managed Tailwind and esbuild tasks:

From the umbrella root:

```sh
mix phx.server
mix test
```

To build the web assets explicitly, run from `apps/web`:

```sh
mix assets.build
```

In development, Phoenix watches `assets/css` and `assets/js`. Production builds
run `cd apps/web && mix assets.deploy` before the release is assembled.
