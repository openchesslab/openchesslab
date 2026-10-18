# OpenChessLab — TODO

> Overzicht van openstaand en mogelijk werk. **Geen vastgelegde volgorde**; de actuele slice
> staat in [`docs/HANDOFF.md`](docs/HANDOFF.md), architectuurgrenzen in
> [`docs/architecture.md`](docs/architecture.md), rationale/metingen in
> [`docs/development-history.md`](docs/development-history.md). Werk dit bestand bij bij elke
> slice: afgerondes weg, nieuwe erbij. Eén regel per item, details horen in de docs.

## Actief (lopende slice)

- [ ] **Deploy** van de analyses-tabbar- + importdialoog-herwerking (4 commits, getest,
      wacht op expliciete gebruikerstoestemming).
- [ ] **DSM/shm op de mpg bewaken** — parallelle queryplannen falen met "could not resize
      shared memory segment" (16 MB); boekquery vermijdt die via index-vorm, maar grote
      aggregaties kunnen er tegenaan lopen. Eventueel planvorming bijsturen of mpg-klasse
      verhogen bij meer corpus.
- [ ] **Incident root-cause** — transient import-falen bij ~264.917 (PostgreSQL-error
      `db=4,1ms`, niet reproduceerbaar); serverlog-check met sudo staat bij de gebruiker uit.

## Bulk-import & corpus

- [ ] **Run-hygiene bij handgestuurde imports** — resultaat altijd `IO.inspect`en
      (`mix run -e` print niets), logniveau begrenzen (debugruns schreven 919 MB logs),
      voortgangschecks op het beam-proces richten (`pgrep -f` matcht de eigen shell).
- [ ] **Staging-tabel-POC** — 10k games via `UNLOGGED` staging + set-based dedup/inserts;
      vergelijk games/s, totaaltijd en WAL met het huidige pad (nu: 90 → 53 games/s bij
      ~20M posities). Alleen doorvoeren bij meetbare winst zonder correctieverlies
      (dedup-semantiek identiek).
- [ ] **Tijdelijke PG-tuning tijdens import** — `synchronous_commit=off`, grotere
      `max_wal_size`/`maintenance_work_mem`, autovacuum uit; na afloop terugzetten.
- [ ] **`position_features`-opslag heroverwegen** — GIN-index is ~27% van ~56 KB/partij;
      corpusambitie (10M partijen ≈ 560 GB) vereist hier een bewuste keuze.
- [ ] **Pre-2014 SAN-disambiguatie** — parser ondersteunt geen van-vak-vorm (`Rc8c6`);
      12% failures op 2013-dumps, 0% modern. Alleen relevant bij oude historie.
- [ ] **Bron-filter in de zoek-UI** — `source`/`source_detail` zitten nu in record-metadata
      (`f440c00`); bron-dropdown in de zoekmodal + query-time tempo-filter (`time_control`)
      voor zoeken/opening boek.
- [ ] **Bulk delete per bron** — nu mogelijk via metadata; beleid en (indien nodig) een
      expressie-index op `metadata ->> 'source'` pas toevoegen bij concrete behoefte.

## Zoeken & features

- [ ] **Position similarity productiseren** — digest is gebenchmarkt (`b5caa3f`, 400k
      posities): productie-tabel + backfill + zoekmode-UI (top-24). Herverifiëren op
      ≥10M posities vóór acceptatie.
- [ ] **Feature-catalogus als zoekmachine** — geïndexeerde plan/gelijkenis-queries op
      schaal (Greek gift, IQP, structurele buren) zijn **planned**, geen bestaand vermogen;
      precision + fysieke indexen eerst benchmarken.
- [ ] **`GameSearch.corpus_size/0`** — exacte `count(*)` per modal-open; herzien vóór
      10M+ rijen (cache of schatting).
- [ ] **NL-vertaling feature-omschrijvingen** — 371 curated EN-regels; NL valt terug op EN.

## Bibliotheek, rooms & rechten

- [ ] **Room-ownership permissies** — eigenaarsrechten/beheer verder uitwerken (planned,
      AGENTS.md); nu: owner + members + invites, geen rollen.
- [ ] **Privé position setup/tools** in de editor (bord opstellen, FEN).
- [ ] **Orphaned analyses opruimen** — losgemaakte persoonlijke kopieën na
      accountverwijdering/ontkoppeling; aparte cleanup-slice.

## Import & accounts

- [ ] **Recurring Lichess-refresh** — geplande periodieke sync bovenop de opt-in
      background sync (planned, AGENTS.md).
- [ ] **Lichess-studies importeren** — aparte consent-flow met extra OAuth-scopes (later).

## Techniek & hygiene

- [ ] **`:invalid_occurrences` suite-flake** — seed 938846, AnalysesTest/
      PgnBatchImporterTest; gedocumenteerde backlog (development-history §7). Reproduceren,
      oorzaak vinden; **niet onderdrukken** en geen falende run groen noemen.
- [ ] **`PositionProperties` opruimen** — voedt alleen nog de MATERIAL/SPACE-tabs;
      highlights lopen via de Features-catalogus.
- [ ] **Observability & load benchmarks** — productie-monitoring, queryprestaties op
      groeiende corpus; importqueue/regio-uitbreiding pas bij concrete behoefte.
- [ ] **architecture.md-verstjaring** — zoekmodal-paragraaf noemt nog "provider tabs =
      demo fixtures"; dat is sinds de import-herwerking (`f944950` e.v.) achterhaald.
- [ ] **Internationale SAN-notatie** — later; geen licentie om notatie-semantiek nu te wijzigen.
- [ ] **Engine** — eventueel multithreading (COOP/COEP) of server-engine; beide later.
