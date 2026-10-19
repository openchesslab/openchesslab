# OpenChessLab ops dashboard

Grafana-dashboard bij de Prometheus-metrics van OpenChessLab (zie
`apps/web/lib/web/telemetry.ex` voor de series en `fly.toml` `[metrics]` voor
de scrape-configuratie).

## Importeren (eenmalig)

1. Open <https://fly-metrics.net> en log in met je Fly-account.
2. Ga naar **Dashboards → New → Import**.
3. Upload `ops/grafana/openchesslab.json` (of plak de inhoud).
4. Kies bij **Prometheus** de voorgeconfigureerde Fly.io-datasource.
5. Klaar — het dashboard verschijnt als "OpenChessLab" (uid `openchesslab-ops`).

Wijzigingen in de JSON kunnen op dezelfde manier opnieuw geïmporteerd worden
(Grafana overschrijft op `uid`).

## Wat staat erop

- **Gezondheid** — BEAM-geheugen (drempel op 512 MB), run queues, VM-tellingen
- **Verkeer en LiveView** — endpoint-latentie (p50/p95/p99), router-dispatch
  p95 per route, request-rate per status, LiveView mount/event-latentie
- **Database** — repo querytijd en pool-wachttijd (onze eigen series),
  PG cache-hit-ratio, databasegrootte (belangrijkste trend tijdens de
  digest-backfill), verbindingen, edge-responses

Alle query's filteren op `app="openchesslab"`; de PG-series zijn bedoeld als
Fly's ingebouwde postgres-metrics van dezelfde organisatie. **Let op:** die
series zijn in de Fly-docs op unmanaged postgres gebaseerd — exporteert de
Managed Postgres ze niet mee, dan blijven die drie panelen leeg (geen schade;
de rest werkt). Check in Explore of `pg_database_size_bytes` serie heeft;
zoniet, kijken we later naar MPG-eigen metrics.
