# OpenChessLab — overdracht voor Codex en OpenCode Go

Bijgewerkt: 2026-10-18. Dit is het compacte startpunt voor een andere laptop of agent.
Git en de actuele broncode zijn leidend. Werk dit bestand bij bij iedere slice en vóór een onderbreking:
status, resterende stappen, uitgevoerde tests, commit/push en deployment afzonderlijk.
Geen geheimen, tokens of lokale databases opnemen.

## Modelkeuze

**Codex:** de gebruiker heeft Sol Light/Medium en Astra Light/Medium beschikbaar.
Voor Google-login en accountkoppeling is Astra Medium geadviseerd; de gebruiker heeft
bevestigd te zijn overgeschakeld. Adviseer bij volgende slices alleen beschikbare opties.
Bij een zinvolle modelwissel: geef de reden en wacht eerst op de gebruiker.

**OpenCode Go:** startadvies voor de volgende slice is **Kimi K3**.
De actuele officiële lijst vermeldt zowel Kimi K3 als Kimi K2.7 Code; K2.7 is dus niet
uit die lijst verdwenen. K3 heeft volgens die pagina strakkere gebruiksruimte dan K2.7.
Controleer vóór ieder nieuw advies de nieuwste officiële Go-documentatie en de beschikbare
modellen via /models; baseer het advies niet op een oude naam of zoekmachine-samenvatting.
Model-ID uit de actuele documentatie: `opencode-go/kimi-k3`.

Verbind in OpenCode via `/connect` → OpenCode Go en kies via `/models`.
De officiële [Go-documentatie](https://opencode.ai/v2/docs/console/go)
is geopend en gecontroleerd op 2026-10-14; beschikbaarheid kan veranderen.
Bewaar API-sleutels via OpenCode, nooit in de repository.

Geef voortaan bij een nieuwe slice kort het geadviseerde Codex-model en reasoningniveau aan.
Meld expliciet wanneer een wissel zinvol is, met één concrete reden; laat de gebruiker wisselen.
Adviseer geen onnodige wissels en claim niet dat een modelwissel al is uitgevoerd.

## Repository en huidige status

- **Zoek-roadmap (besloten 2026-10-18).** Doel: zoeken naar partijen én posities als USP.
  **Fase 1** partijzoeken volwassen (ECO/opening/event + verrijkte regels ✅ `2cc72fe`;
  trigram-indexen ✅ `98e5e78` — speler-ILIKE op bench 316 ms seq → 1,1 ms bitmap scan,
  4 indexen geverifieerd in productie; sorteren ✅ `cc44146` — partij-zoekopdrachten zónder
  FEN lopen nu record-gedreven **nieuwste-eerst** (`(COALESCE(date,''), id)`-btree + keyset,
  één rij per partij via LATERAL; mét FEN blijft de positiegedreven insertion-order;
  `:date_desc` + positiepredicaat = expliciete `:unsupported_sort`; bench: 0,05 ms/pagina
  match-all, 0,79 ms met spelerfilter; nog: ply-deeplinks). **Fase 2** featurezoeken:
  digest-atomen (intrinsieke catalogue-feiten: `motifs.greek_gift`, `pawns.iqp`, …) in de
  vorm van de oude `position_features.properties` (bytea[] + GIN, hercodering i.p.v. nieuwe
  tabel), POC op ~100K posities met EXPLAIN-bewijs vóór de volledige 19,7M-backfill;
  cross-side OR (record- OF positiepredicaat) en query-transformaties (kleurwissel/
  spiegeling). NB: `position_feature_vectors` (jsonb) is leeg — de backfill/indexfase stond
  sinds 2026-10-13 als "planned" en is nooit ingepland. **Fase 3** search-by-example +
  materiaalsubstituties + prefilter/rerank relevantie. **Fase 4** zettenpad/eindspel.

- **Afgerond (2026-10-18), gedeployed:** **Chess.com-maandkiezer + selectie-UX + dialyzer +
  twee kleine fixes.** (1) Het tekst-maandveld is vervangen door een **archives-dropdown** (gelokaliseerde maanden
  mét partijen, nieuwste vooraf) met prefetch op het username-veld; vóór invoer toont een
  **disabled placeholder-dropdown** ("Latest month"/"Laatste maand"), het tekstveld bestaat
  alleen nog als eerlijke fallback bij een archives-fout. (2) De tray start **gedeselecteerd**
  met een driestand-master-checkbox. (3) **Dialyxir toegevoegd** (gebruiker) en de eerste
  drie warnings opgelost: dode error-tak in `Rooms.remove_analysis/3` (RoomServer levert
  altijd `:ok`), dode `|| []` op `cached.lines`, en de highlights-pijplijn van typespecs
  voorzien — de resterende `call_without_opaque` is de OTP 29-:sets-kwestie (opaak in
  `MapSet.union`-spec vs concrete inferentie) en is gericht onderdrukt met
  `@dialyzer {:no_opaque, compute_highlights: 4}` + toelichting. `mix dialyzer` is nu groen
  (0 errors). (4) De tab-containers van de importdialoog kregen 2px padding zodat de globale
  `:focus-visible`-outline niet meer door `overflow-hidden` wordt afgekapt. (5) Op mobiel
  (≤860px) rendert het features-paneel nu **na** het zetten-paneel (was ervoor): bord →
  engine → zetten/statistieken → features. Suites: web **304**, analysis **670**.
  Browsergeverifieerd (placeholder → dropdown na typen; focus-ring rondom zichtbaar;
  mobiele volgorde op 390px).

- **Afgerond (2026-10-18): feature-review fase 2, laag 1 (python-chess-orakel).** Drie
  scripts (`feature_oracle_export/check.exs` + `feature_oracle.py`, venv in
  `/tmp/opencode/venv-oracle`) vergelijken de catalogus met python-chess op 818
  willekeurige bench-posities. **Twee echte bugs gevonden én verholpen:** (1)
  **en-passant-movegen** (`Features.Chess.Movegen`): ep-zetten werden gegenereerd voor de
  verkeerde kant/vanaf de verkeerde rij (`f2g3`) wanneer het ep-target op de rij van de
  andere kleur stond — rij-guard toegevoegd (wit: index 5, zwart: index 2) + tests;
  (2) **`TacticMap.checks/2`** telde pseudo-legale "checks" zonder eigen-koning-veiligheid
  (o.a. koningen naast elkaar) — nu hetzelfde legaliteitsfilter als `legal_moves` + test.
  Eindstand: **alle 7 oracle-paren 0/818** (attacked_pieces, defended, legal_moves,
  per_side, absolute_pin, aantal_checks, check). Suites: features 217, analysis 670
  (feature-telling 371→372), web 297. Volgende lagen: semantische review per sectie.

- **Afgerond (2026-10-18): fase-2 eerste beslissing — `squares.enemy_on_outpost`.** Na de
  fase-1-finding (PP telt vijandelijk bezette outposts, catalogus niet) koos de gebruiker
  optie B: de catalogus uitgebreid met een nieuwe sectie-8-feature die vijandelijke stukken
  op je outpost-velden toont (tactisch doelwit; de term "outpost" is online verdeeld —
  veld-eigenschap vs. bruikbaarheid). Bestaande twee outpost-features ongemoeid; PP/keys
  ongemoeid (geen herberekening). EN-beschrijving + spec-bullet + tests (minimale fixture,
  fase-1-FEN met dubbele richting e5/d4, negatieve gevallen). Features **215**, web **297**.

- **Afgerond (2026-10-18): feature-review fase 1 (mechanische alignment).** Script
  `apps/analysis/benchmarks/feature_alignment.exs` (`47f94c0`) vergelijkt de catalogus met
  `Chess.PositionProperties` op willekeurige bench-posities. **Uitslag (791 posities): 0 bugs**
  — 9/9 direct vergelijkbare paren exact gelijk (attacked_pieces, defended_squares, open/
  semi-open files, material counts/total, castling, side-to-move, en_passant). Twee
  **definitieverschillen, identiteit bewezen**: (1) `attacks.map`/`space` telt de catalogus
  eigen bezette velden mee in dekking, PP maskeert die (`catalogus − chess == verdedigde
  eigen stukken`, 0/791); (2) `squares.outpost`: PP telt vijandelijk bezette outpost-velden
  mee, catalogus alleen leeg + eigen-bezet (7,8% van posities) — **productbeslissing voor
  fase 2**, geen rekenfout. Fase 2 (semantische review per sectie) volgt; modeladvies:
  Kimi K3 hoge reasoning.

- **Afgerond (2026-10-18), nog níet gedeployed:** **engine-UI in de zetlijst à la Lichess**
  (twee iteraties; de tweede volgt lichess.org/analysis exact). Eindvorm: middelste kolom =
  features permanent; rechterkolom van boven naar beneden: **engine-balk** (toggle + grote
  eval + naam/depth + tandwiel), **compacte PV's** (doorlopende tekstlijnen, spans klikbaar,
  peek/play behouden, `#engine-pv`), **grafiek**, **zetlijst met eval-chips**, review,
  reference-paneel. Stats-grid (nodes/nps) vervallen. Tests: 297 groen — nodes/nps-asserts
  vervangen, PV-selector `#engine-pv button`. **Test-suite-vertraging opgelost:** de
  onvoorwaardelijke feature-load kostte per test-render een volledige 371-kenmerken-extractie
  + write (suite 13 s → ~100 s); nu `Application.get_env(:web, :features_autoload)` met
  `false` in test.exs en expliciete opt-in (`with_features_autoload()`) in de 10
  feature-tests. Middelste kolom = altijd de features-
  catalogus (engine/features-tab weg, `select-engine-tab` en `tab_class` dood);
  rechterkolom: compacte toolbar (settings+tandwiel) boven de zetlijst, **eval-chips per
  zet** uit de gedeelde eval-store (`@engine_evals` → `live_evals` in `move_list`,
  entries kregen `position_id`), daaronder eval-stats, PV (met `#engine-pv`), grafiek,
  review; reference-paneel ongemoeid. Features laden nu onvoorwaardelijk
  (`maybe_load_features`). Regressietest: chip −0.20 op e4 na engine-update
  (wit-relatief). Browsergeverifieerd: chips/stats/PV/grafiek/features tegelijk zichtbaar
  (screenshot). Serieel: web **297**; formatter, diffcontrole.

- **Afgerond en gedeployed (2026-10-18):** drie fixes/slices bovenop de corpus-transfer.
  (1) **DSM/parallel-fix voor de boekquery op de startpos:** de reference-panel-query
  (`count(DISTINCT)` + join over 277k occurrences) koos een parallel plan dat op de kleine
  mpg-shm faalde ("could not resize shared memory segment") → panel toonde "could not be
  loaded" alleen op de heetste stelling. Fix zonder deploy: `ALTER TABLE game_occurrences
  SET (parallel_workers = 0)` (storage-parameter, persistent, door mij direct uitgevoerd;
  gebruiker heeft geverifieerd dat de startpos-boek nu laadt).
  (2) **MATERIAL/SPACE-strip verwijderd** (`6b4687a`): beide tabs dupliceerden de
  features-catalogus (`material.count.*`/`total_value`/`difference`,
  `space.enemy_half_control`); strip-UI, JS-preference-plumbing, i18n-keys en dode helpers
  weg + twee pre-existing clause-groep-warnings opgelost (web 296). `PositionProperties`
  voedt nu niets meer in de UI (prune = aparte slice, TODO).
  (3) **Chat-historie-fix** (web 297): de drawer toonde geen berichten die vóór het joinen
  of sluiten arriveerden — de `phx-update=stream`-container bestaat alleen bij open
  drawer, dus mount-stream-items bereikten de client nooit; `open-chat` reset de stream nu
  vanuit `@chat_messages` (`stream(..., reset: true)`) + regressietest; live in de browser
  geverifieerd met twee tabs.

- **Bezig (2026-10-18): Elite-database-experiment lokaal.** Aanleiding: de bulk-import vanaf
  de 2-vCPU worker deed 4,8 games/s (6,3 uur voor 109k); de bottleneck was worker-CPU +
  gedeelde DB — níet de scan en níet de transacties (dedup-lock + per-partij-atomiciteit
  zijn load-bearing: `games` heeft géén unique constraint op fingerprint/content).
  Greenfield (geen gebruikers) maakt wipe+vervanging mogelijk.
  - Bron: **Lichess Elite Database** (database.nikonoel.fr, CC0-afgeleid): 2400+/2200+ t/m
    nov 2021, 2500+/2300+ vanaf dec 2021, geen bullet; maandzips ~65–260 MB.
  - Benchmark november 2025 (280.246 partijen) in `openchesslab_bench`: 20k-run
    **90 games/s** (~19× de worker), 4 malformed, 0 failures.
  - Ons filter blijft nodig: niet voor Elo (0 partijen < 2200), wél voor `TimeControl < 180`
    — 768 bullet-achtige partijen (0,3%) zitten in het Elite "Blitz"-bestand.
  - Groei gemeten: **~46 MB per 1.000 partijen** (~75 posities/partij); één maand ≈
    13 GB / ~21M posities.
  - Fly mpg `openchesslab` (basic, AMS, id `w8675081zgnr3pk4`): **30 GB disk** — één maand
    erbij ≈ 22/30 GB; meer historie vereist disk-resize of bewuste scope-beperking.
  - **Herkomstmarkering geïmplementeerd (`f440c00`, analysis 670 / web 296 groen):**
    `BulkImport` `:source`/`:source_detail` → metadata op elk record; `PgnAnalysisImporter`
    `:source` → `"pgn"`/`"lichess"`/`"chesscom"` bij kamer-imports, `"lichess"` bij
    LibraryImport/sync; dedup blijft puur content (bron staat op het concrete record).
    `keep_game?` kreeg `:allow_bullet` (default uit) — elite-imports nemen óók de snelle
    partijen mee (2500+-spelers; `time_control` zit in metadata dus query-time filteren op
    tempo blijft mogelijk bij zoeken/opening-boek).
  - **Volledige november-import afgerond in `openchesslab_bench` (2026-10-18):** 280.246
    gelezen, **280.155 records** (91 malformed, 0 failures), **277.005 canonieke games**
    (1,1% gedupliceerde records), **19.748.363 posities**, 24,9M occurrences, **16 GB**
    (positions 6,2 GB · occurrences 6,0 GB · position_features 3,7 GB ≈ 23%). Alle records
    dragen `source=lichess-elite` + `source_detail=2025-11` (0 ongelabeld); tempo-verdeling
    180+0 193k / 180+2 51k / 180+1 7,8k / 600+0 7,3k. Tempo zakte 90 → 53 games/s naarmate
    `positions` groeide (dedup + index-onderhoud).
  - **Incident (transient, niet root-gecaused):** eerste run stopte stilletjes bij ~264.917
    — één INSERT in `games` kreeg een PostgreSQL-fout (`db=4,1ms`), batch rolde terug,
    `run/1` retourneerde `{:error, ...}` maar `mix run -e` print geen return-waarden.
    Repro van dezelfde 100 partijen slaagt zowel in een schone DB als in bench: **niet
    data- of toestandsafhankelijk**. Serverlog vereist sudo (gebruiker gevraagd:
    `sudo journalctl -u postgresql --since "10:05" --until "10:20"`). Hervat met
    `skip = offset = max-suffix` (id's = input-ordinals; malformed-herverwerking is
    onschuldig): 15.325 records in ~5 min, 0 failures. Lessen: resultaat altijd
    `IO.inspect`en, logniveau begrenzen (919 MB debug-log!), voortgangschecks op het
    beam-proces i.p.v. `pgrep -f` (matchte de eigen shell → valse RUNNING).
  - **Transfer naar productie (2026-10-18, gebruikersbeslissing: volledige wipe, óók
    accounts):** prod-inventaris vooraf 175.782 records (source NULL), 174.462 games,
    14,15M posities, 49 rooms, 59 analyses, 1 bibliotheekentry. Uitgevoerd: dump 786 MB
    (`pg_dump -Fc -Z6 --data-only`, 5 corpus-tabellen) → prod álle tabellen gedropt +
    release-migraties opnieuw (openings 3.865 opnieuw geseed) → 7 grote indexen gedropt →
    `pg_restore --data-only` via `fly proxy 15432:5432 fdaa:ca:a87:0:1::2 -a openchesslab`
    (direct-IP; credentials stil uit `DATABASE_URL`). **Incidenten:** (1) `--jobs=4` liet
    `game_occurrences` starten vóór `positions` klaar was → FK-breach (data-only dumps
    kennen géén TOC-afhankelijkheden; parallel alleen bij afwezige FK's); (2) mpg-diskdruk
    (dode heaps + temp indexbestanden + WAL-opstapeling) veroorzaakte commit-stalls én één
    servercrash — hersteld automatisch; (3) de FK-trigger probe per occurrence-rij
    (~8k rijen/s) was de traagste stap. **Winnende aanpak voor occurrences:** TRUNCATE,
    beide FK-constraints én de pkey droppen, COPY via psql met `SET synchronous_commit=off`
    (heap-only, ~150 MB/min), daarna PK/FK's set-based terug en indexen herbouwen.
    `ALTER DATABASE`/`ALTER ROLE` mag niet (MPG-systeemrollen), `pg_cancel_backend` wél via
    `SET ROLE "fly-user"`. Sequences kloppen exact (dump SEQUENCE SET-items: positions
    24.245.511, games 277.012, records 280.261 = bench-max). Lokale PG is 18.6, mpg is ouder
    (`transaction_timeout` SET faalt onschuldig bij elke pg_restore-sessie).
    **Bij controle bleek óók `position_features` slachtoffer van dezelfde parallelle
    FK-race** (COPY failed op `position_id`, stilletjes "finished", 0 rijen met 3,4 GB
    dode heap) — zelfde behandeling als occurrences: TRUNCATE, pkey/FK/GIN droppen,
    heap-only COPY met `synchronous_commit=off`, daarna terugzetten. Les: **parallelle
    data-only restores met FK's niet doen**; bij controle álle tabellen tellen, niet alleen
    de gefaalde. Indexen: 16/16 aanwezig; ANALYZE gedraaid.
  - **TRANSFER AFGEROND (2026-10-18 ~16:30):** productie draait nu de elite-november-corpus —
    games 277.005, records 280.155 (allen `source=lichess-elite`/`2025-11`), posities
    19.748.363, occurrences 24.909.151, features 19.748.363 (exact bench), 16/16 indexen,
    4/4 FK's gevalideerd, sequences = bench-max, **15 GB** van 30. Boek-smoketest op de
    startpos (id 837): e2e4 133.004 · d2d4 87.823 · g1f3 28.641 · c2c4 16.016 met W/D/L-
    uitsplitsing — startpos is id 837 omdat ids insertvolgorde volgen (vandaar ook de
    FK-race op precies die positie). Identiteit is gewist (nieuwe logins maken verse
    users). Te monitoren: **DSM/shm is klein op de mpg** — parallelle queryplannen falen
    met "could not resize shared memory segment"; de boekquery in de app vermijdt die via
    index-vorm, maar grote aggregaties kunnen er tegenaan lopen. Identieke corpus blijft
    lokaal in `openchesslab_bench`; dump 786 MB in `/tmp/opencode/corpus-elite.dump`.

- **Bulk-import afgerond (2026-10-18 01:32 UTC):** `bulk-resume-3` eindigde met exit 0 —
  `source: :ok`, 89,6M partijen gelezen, 109.798 gehouden, **109.523 geïmporteerd**
  (275 malformed, 0 failures), ~6,3 uur à gemiddeld 3.955 games/s. Machine staat gestopt
  (restart policy `no`). Corpus-tellers via ssh-eval op de app-machine
  (`Application.ensure_all_started(:database)` — níet `:web`: die bindt poort 8080 en faalt
  in een eval-node): **games 174.462**, **game_records 175.782**, **positions 14.154.117**.

- **Afgerond (2026-10-18), nog níet gedeployed:** de analyses-tabbar- en importdialoog-herwerking,
  in vier commits:
  `599e0b8` (tabs noemen een game-analyse naar de spelers ("Wit – Zwart" uit de
  game-record-metadata via `GameRecords.get/1` in `AnalysisView.room_analyses/2`); tooltip met
  event/datum/resultaat/start/revisie; dezelfde metadata als regel boven het bord,
  `#analysis-game-info`), `2689e66` (middle-click sluiten via nieuwe `AnalysisTabs`-hook:
  `auxclick` → `request-remove-analysis` met dezelfde bevestigingsdialoog, `mousedown`
  voorkomt autoscroll; actieve chip scrollt in beeld bij `updated`), `01687fb` (overflow: bij
  >10 analyses 9 chips + **More-menu** met selectie en ×; de geselecteerde tab blijft altijd
  als chip zichtbaar — `AnalysisView.tab_split/2`), `aab0a21` (importdialoog scrollt niet meer
  zelf: header/tabs vast, alleen de tray-lijst scrollt intern; **checkout-bar** vast onderaan
  met Alles/Niets (pas bij >5 rijen), samenvatting "{selected} of {total} selected" en de
  count-aware importknop — lange maand-archieven duwen de actie niet meer uit beeld).
  **Browsercheck op dev-room F8SUU4 (echte chess.com-API):** PGN met metadata → chip "Nakamura,
  Hikaru – Martinez, Josep" + metadataregel boven bord; 13 analyses → 8 chips + actieve chip +
  More (4), selectie uit het menu wisselt naar een chip; middle-click op chip opent de
  verwijderbevestiging; chess.com-tray (hikaru 2026-10) 308 rijen scrollt intern terwijl de
  checkout-bar onderaan blijft (visueel geverifieerd met screenshot). Serieel: web **296**
  (2 nieuwe tests), analysis **666** (3/4 runs; één run toonde een enkele failure waarvan de
  output alleen als tail bewaard bleef — drie daaropvolgende volledige runs groen, geen
  wijzigingen in de analysis-app deze sessie); formatter + `git diff --check` schoon.
  architecture.md bijgewerkt (room shell + importdialoog-paragraaf). Deploy pas na expliciete
  toestemming.

- **Afgerond en gedeployed (toestemming gegeven 2026-10-17); productie gezond:** de
  import-herwerking is klaar, in vijf commits op de domein-slice `f944950`:
  `8f77b4b` (metadata-fetchers: `GameImport.fetch_lichess_recent_games/2` → NDJSON-rijen
  `%{id, white, black, result, speed, year}`; `fetch_chesscom_month_games/3` → rijen incl.
  `pgn`, `url` als id, nieuwste eerst), `d0e8086` (vier keep-checkboxes in de modal-footer
  voor élke PGN-bron → `run_imports` → `PgnAnalysisImporter.import(..., opts)`; default
  comments/variations/metadata aan, engine-annotaties uit), `3386908` (**bugfix, zie
  hieronder**), `0364061` (provider-tabs zijn nu **selectie-trays**: laden → rijen met
  checkbox "Wit – Zwart, resultaat, speed · jaar", alles/niets, count-aware knop
  "Import N game(s)"; lichess haalt de selectie via `fetch_lichess_games_by_ids/1`,
  chess.com importeert uit de al geladen maand-PGN's zonder refetch; gekoppeld account
  vult de username voor via de grant; oude max-count-formulieren en de fetchers
  `fetch_lichess_user_games`/`fetch_chesscom_user_games` + dode i18n-keys weg),
  `ffd23cd` (zetlijst toont `evaluation` klein mono en `clock` klein muted tabular-nums
  naast de zet; `Node.clock/1`/`Node.evaluation/1` accessoren; entries uit
  `AnalysisView.move_list_data`).
  **Bugfix `3386908` (self-echo):** `Analyses.play` publiceert `:analysis_changed` naar
  álle subscribers, ook de LV die zelf de zet deed — die las opnieuw en startte een
  tweede `start_reference`-async die de eerste (reset: true) verdrong terwijl diens
  neveneffecten (externe tablebase-call + cache-put) al liepen. In tests crashte de
  tweede fetch op de lege stub-queue (~30% flake in de endgame-test); in productie kostte
  elke zet in eindspel een dubbele externe call. Nu: `handle_info(:analysis_changed)`
  slaat de reload over als de opgehaalde revisie gelijk is aan de gehouden revisie
  (eigen echo); vreemde wijzigingen (revisie > eigen) laden wél. 8/8 runs groen.
  **Browsercheck op UIUX01 (echte API's):** lichess-tray 25 rijen (DrNykterstein), alles
  voorselecteerd, "Import 25 games" → niets → "Import 0 games" disabled → 2 aangevinkt →
  "Import 2 games" → 2 chips erbij; chess.com-tray (hikaru, maand 2026-10) 308 rijen, 1
  geïmporteerd zonder refetch; geannoteerde PGN met annotations aan → zetlijst
  "1. e4 0.20 0:05:00 e5 0:04:55". Serieel: analysis **666**, web **293**; formatter,
  diffcontrole. architecture.md bijgewerkt (tray-paragraaf).
  **Deploy 21:41 UTC:** image `01M55WZ1S6…`; release-migratie groen (geen nieuwe
  migraties), beide health checks passing, `/health` + `/ready` 200, exact één app-machine.
  De deploy-waarschuwing "not listening on 0.0.0.0:8080" was een timing-artefact van de
  socket-scan (beam nog aan het opstarten); checks daarna groen. `bulk-resume-3` liep
  ongestoord door op zijn eigen image (21:34→21:39: kept 18.580 → 20.791).
  **Import-achtergrondwacht (afgerond):** `bulk-resume-3` herstartte 19:14 na de
  serverherstart, skip-scan 35,6M op ~6.180 games/s, grens gepasseerd 20:52 — kept groeit
  (21:25: 14.499). Groeicheck (corpus-teller > 66.237) geslaagd. Machine draait op de
  actuele image-tag (01M55KPBR…, zelfde als web).

- **Afgerond (benchmark-slice; bewust nog níet gedeployed als productiefeature):** `Add the
  position similarity digest and its search benchmark` (`b5caa3f`). Eerste S2-stap: de digest +
  meetkring, nog géén tabel/backfill/UI. `Analysis.PositionSimilarity.digest/1` pakt per stelling:
  side-to-move, castling (4 bits), materiaalmultiset (10 nibbles, exact), beide koningsvelden
  (12 bits), open/semi-open lijnmaskers — alles pure bord-reads (geen movegen/extractie).
  Pionnenstructuur blijft op `positions.white_pawns/black_pawns`. Benchmark op de dev-corpus
  (398.170 echte posities → bench-DB): digest+decode+insert **~42k posities/s**; structuur +
  materiaal narrowing geeft **1–9 kandidaten** per steekproef en de gerankte top-24 draait in
  **≤ 0,09 ms**; materiaal-alleen is onbruikbaar vroeg in de partij (top-key = 31k posities, 8%).
  De enige echte flood = openingstellingen (gedeelde structuur én materiaal) — minst interessant
  geval; top-N blijft begrensd. Les van vandaag: de harness ving **drie** typefouten in mijn
  FEN-fixtures (PPPP1PPP i.p.v. PPPPPPPP, rank-mixup, castling-validatie) — fixtures blijven
  tweeksnijdig. Serieel: analysis **663**; formatter, diffcontrole. Volgende stap: productie-tabel
  + import-time/backfill + zoekmode-UI (top-24, geen paging), met herberekening op ≥10M posities.

- **Afgerond en gedeployed; productie gezond:** `Fix duplicate en-passant-target moves, phantom
  castles and stale rook-capture castling rights` (`7afa835`) + `Add a differential engine
  harness between Chess and Features.Chess` (`881dd6c`) + `Skip malformed dump games in grouped
  bulk import` (`c38a008`). De F2-slice (differentiële validatie) werd eerst gedaan omdat hij de
  rest ontregelt — en hij vond meteen drie **echte productiebugs in de gameplay-engine**:
  (1) `legal_moves` dubbelde een zet naar het en-passant-doelveld wanneer een schuifstuk (loper)
      dat veld ook rustig kon betreden (ep-kandidaten filterden niet op pion) — +1 op Kiwipete d3;
  (2) spookcastling: `special_candidate_moves` stelde rochades voor óók als e1/e8 geen koning
      hield; `apply_move` behandelde ze dan als legale torenzetten (duplicaat van de torenzet);
  (3) een toren die van zijn thuisveld **sloeg** verloor zijn rochaderecht niet (capture-pad
      miste de moving-side update) — een bestaande test droeg de foute verwachting en is
      gecorrigeerd. Ankers: zes perft-posities met gepubliceerde/oracle-geverifieerde tellingen
      (`Chess.PerftTest`; python-chess als referentie-orakel in een tijdelijke venv, niets
      geïnstalleerd buiten /tmp). De differentiële harness
      (`apps/features/test/features/engine_differential_test.exs`) vergelijkt perft + geparseerde
      state + 30 seeded random games (zetverzamelingen én veld-voor-veld staat); de
      en-passant-conventie is gedocumenteerd en genormaliseerd (Chess nilt een nutteloos
      ep-doelveld, Features bewaart het ruwe veld — zetten identiek). Let op: de harness ving
      eerst twéé typefouten in mijn eigen FEN-fixtures. Serieel: chess **595**, features **214**,
      analysis **660**, web **288**.
  **Open forensiek (import):** resume-2 abortte op een malvorme dump-game ("No moves found", read
  40.262.969) — daarvoor is nu `skip_malformed` — MAAR de 9.178 records ervan ontbraken terwijl
  games/occurrences wél persisteerden (9.121 orphan-games, ids 65.802..74.922). Dat is onmogelijk
  binnen één committende transactie; dev-repro én een prod-smoke-test (356 records) persisteren
  wél. Oplossen als het terugkomt: resume-3 logt vroeg genoeg om het te zien. **Resume-3 draait**
  (skip 35,6M — bewezen grens — offset 66.253; healt de orphans via find-or-create). Watcher met
  vroege groeicheck (~105 min): dan moet de corpus-teller boven 66.237 staan; zo niet → killen en
  uitzoeken, niet door laten draaien.

- **Afgerond en gedeployed; productie gezond:** `Enrich corpus search with previews, rating/date
  filters and structure modes` (`c4ffe56`). Eerste zoek-slice na de discussie ("search is een
  beetje embarrassing"): de kamer-modal blíjft de zoekplek (de aparte-pagina-variant is
  vervallen — je moet niet je kamer verlaten om een partij erin te openen). Nieuw: **minibord-
  preview** van de gematchte stelling per treffer (statisch component, één gebatcherde
  `PositionStore.get_many/1` per pagina — geen N+1), **ratingfilter** (min/max, geldt voor beide
  spelers; `metadata_int_between/3` met cijfer-guard op de JSONB-string), **datumbereik**
  (`metadata_value_between/3`, lexicografisch op `YYYY.MM.DD`), de **vijf al bestaande
  structuur-nabijheden** als modes (één pionzet verwijderd, één pionduw, één pion missend,
  kleurverwisseld, gespiegeld), en een **eerlijke corpus-telling** in de kop
  ("Searches the N games stored on this server…", `GameSearch.corpus_size/0`). Tests: compiler-
  ranges (open/gesloten/leeg), rating+date-filters, push/missing/edit-modi met bewust gekozen
  fixtures (occurrence-matching beperkt wat refuteerbaar is — gedocumenteerd in de test),
  preview + teller in de bestaande zoektest. Geverifieerd in dev (10.465 games): modal met alle
  velden, 8 modes in de select, previews tonen de gematchte stelling, count klopt. Serieel:
  analysis **659**, web **288**; formatter, diffcontrole. Eén sneeuwbal-fix meegenomen: de
  heat-helpers in `room_live` stonden tussen de `highlights_for`-clauses (compiler-waarschuwing).

- **Afgerond en gedeployed; productie gezond:** `Draw hinted piece features on the board and cue
  drawable rows` (`e69a2fc`) + `Draw per-side square-count features as board heat maps`
  (`adcdd96`). Op vraag van de gebruiker ("count rook zou de torens kunnen markeren, loperpaar de
  lopers, pionnenstructuur etc."). Drie vermogens:
  (1) **`board`-hint in de catalogus** — `Features.Feature` kreeg een optioneel veld; tien
  aggregaat-features (de vijf `material.count.*`, `material.bishop_pair(.both)`,
  `material.bishops.{same,opposite}_color`, `quality.bishop_pair`, `material.exchange_advantage`)
  noemen hun stuktype(s); de web-engine trekt de velden uit de **huidige stelling**
  (`Chess.Position.pieces/1`) voor elke kant die de waarde bevestigt (count > 0 / vlag true);
  scalaire vlaggen markeren beide kanten. De vector blijft het signaal, de stelling levert de
  locaties — geen nieuwe data of migratie.
  (2) **Heat maps** — per-side maps `veld => aantal` (o.a. `mobility.per_piece`) tekenen in drie
  vaste intensiteiten (blauw/rood 15/30/50%), genormaliseerd op het hoogste aantal op het bord;
  maps zonder veld-sleutels (wing counts, `pawns.structure`) tekenen niet. Nieuwe spans met
  `data-heat-level` (1..3) in `chess_components`.
  (3) **Cue + lezer-hardheid** — rijen die kunnen tekenen krijgen een klein bord-icoon
  (`data-drawable`, tooltip i18n); lijst-van-lijsten (pionnenketens) flatten één niveau; de
  pin-guard gebruikt nu dezelfde engine (dus counts/paren pinnen pas mee als er iets te zien is).
  Tests: catalogus-hint-test (features), rooktelling per kant, eenzijdig loperpaar, ketens,
  heat-niveaus (dame = 3, pion = 1), cue aanwezig/afwezig. Geverifieerd in dev op UIUX01:
  count.rook + bishop_pair gepind → 4+4 getinte velden (torens + lopers per kant), heat van
  `mobility.per_piece` met 4/16/4 niveaus, DOM-check h1/h8 (wit/zwart) en a1 (geen span). Serieel:
  analysis **657**, features **211**, web **286**; formatter, diffcontrole.

- **Afgerond en gedeployed; productie gezond:** `Remove an analysis from the room via the active
  chip` (`a66e8bc`). De **actieve analyse-chip** heeft nu een klein **×** (alleen de actieve; geen
  chipvervuiling, werkt ook op touch); die opent een bevestigingsdialoog ("Remove “…” from this
  room? Analyses in other rooms and library entries that reference it keep working.") met
  Cancel/Remove. Semantiek (gebruikerskeuze): **alleen ontkoppelen** — de analyse blijft bestaan
  zolang een andere kamer of een bibliotheekverwijzing ernaar wijst; is niets meer een verwijzing,
  dan verdwijnt ook het aggregaat (`RoomStore.cleanup_orphaned_analysis/1`, één conditionele
  DELETE op `room_analyses` + `user_analyses`; `room_analyses.analysis_id` heeft géén FK, dus een
  verliezende race laat hooguit een chip achter die de kamer al als "niet beschikbaar" toont).
  `Rooms.remove_analysis/3` (geen andere aanroepers) kreeg deze semantiek. Na verwijderen van de
  actieve analyse springt de kamer naar de eerste resterende; zonder analyses naar de lege staat.
  Domain-tests dekken de drie gevallen (andere kamer / bibliotheekverwijzing / wees) en de web-test
  de hele flow. Geverifieerd in dev op UIUX01: 16→17 chips (wegwerp-analyse), × alleen actief,
  dialoogtekst, bevestigen → 16 chips, URL viel terug op `?a=ui-game-40`, wegwerp-aggregaat uit de
  DB, 3 `ui-*` fixtures intact. Serieel: analysis **657**, web **281**; formatter, diffcontrole.
  Eén web-run gaf eenmalig 80/81 (test niet achterhaald, uitvoer verloren); daarna 9+ runs groen —
  opnieuw waarnemen en wél vastleggen als het terugkomt.

- **Afgerond en gedeployed; productie gezond:** `Mark pinned features in the readout and drop the
  overlay chip row` (`c2dba9d`) + `Give pinned feature rows the full accent treatment` (`771d990`).
  Op verzoek van de gebruiker: de "OP HET BORD"-chiprij is weg
  (die was eigenlijk overbodig — de vijf oude lagen zíjn features — en veroorzaakte verticale
  scrollbalken). Gepinde features zijn nu onmiskenbaar zichtbaar in de lijst zelf:
  **accent-achtergrond + accentbalk links + vet accent op zowel label als waarde** (zelfde taal
  als de actieve analyse-chip; `data-pinned`-attribuut voor tests), klik = uitleg + pin,
  nogmaals = unpin; lege
  features blijven uitleg-only. Bordtinten ongewijzigd (blauw/rood/amber + file-banden).
  Geverifieerd in dev: geen overlay-rij meer, `attacks.defended_squares` + `king.zone` gepind
  (vet + accent), 14 witte tinten, `squares.outpost` op deze stelling leeg → geen pin. Serieel:
  analysis **655**, web **280**; formatter, diffcontrole. **Import-incident opgelost:** de
  hervatting draaide urenlang een **verouderde image-tag** (`01M53F2A…`, van vóór de
  grouped-mode-fix — vandaar de oude logregels zonder `handed` en de stall na de skip-grens);
  de worker is opnieuw gestart met de actuele tag (`01M5541MP…`, dynamisch opgezocht), draait nu
  met `handed=`-logging op ~8,2k games/s. Les: worker-machines moeten de image-tag **dynamisch**
  van de draaiende webmachine halen, nooit hardcoden. Nieuwe watcher actief.

- **Afgerond en gedeployed; productie gezond:** `Pin catalogue features on the board and replace
  the layers block` (`59505d6`). Het LAYERS-blok is weg; onderaan de bordkolom staat nu een
  **"OP HET BORD"-rij** met de vijf oude snelknoppen (Open files, Attacked squares, Defended
  pieces, King zone, Outposts — elk pint het bijbehorende cataloguskenmerk), elke gepinde
  feature uit de leeslijst als verwijderbare chip, en een Clear-knop. Een klik op een rij in de
  Features-tab opent de uitleg én pint de velden op het bord (blauw = wit, rood = zwart, amber =
  neutraal, amber banden = open files; `data-highlight`-attributen voor tests); lege features
  blijven uitleg-only. `room_live` leidt de highlights af uit de ruwe vector (per-side lijsten
  én losse velden zoals `state.king_squares` = `{"white" => "e1"}`, platte lijsten, file-letters);
  het vector wordt ook geladen wanneer er pins staan terwijl de tab dicht is. `PositionProperties`
  voedt alleen nog de MATERIAL/SPACE-tabs (opruimen = vervolg). Geverifieerd in dev: 31/29
  getinte velden bij "Attacked squares", chips actief, Clear werkt, detailstrook + pin in één
  klik. Serieel: analysis **655**, web **280**; formatter, diffcontrole.

- **Afgerond en gedeployed; productie gezond:** `Wrap feature row values and give rows useful
  tooltips and labels` (`c9db165`). Naar aanleiding van de leesbaarheidsfeedback: (1) **waarde
  wikkelt** naar een eigen regel (rechts uitgelijnd) wanneer label+waarde niet naast elkaar passen
  — het label blijft altijd zichtbaar (het krimpt alleen nog als het zélf breder is dan het paneel
  van ~158px); (2) **label-overrides** voor ids met Nederlandse woorden of typefouten
  (`threats.aantal_checks` → "Checks available", `threats.aantal_forcing_moves` → "Forcing moves
  available", `pawns.weak_undeprotectable` → "Weak undefendable pawns"; keys `featureLabels.<id>`,
  EN+NL, fallback blijft de gehumaniseerde id); (3) **tooltip = de omschrijving** uit de
  detailstrook ("Which colour is to move"), niet meer de ruwe id — de id blijft beschikbaar via
  `data-feature` en in de detailstrook. Geverifieerd op 1440×900 (o.a. "Trapped piece": label
  zichtbaar, waarde op regel 2; "Checks available" i.p.v. "Aantal checks"). Serieel: analysis
  **655**, web **280**; formatter, diffcontrole.

- **Afgerond en gedeployed; productie gezond:** `Fix per-side feature values, jsonb double-encoding
  and board stability` (`84e6758`). Drie correcties uit de feature-lijst-discussie:
  (1) **per-side waarden** worden nu per kant gelezen i.p.v. `map_size` ("2" bij lege lijsten!):
  booleans → de ware kant(en) ("White"/"Both"/"—"), lijsten/getallen → "W 2 · B 0", korte
  lijstjes (≤4 korte strings) → bijv. "a, d"; lege rijen dimmen (opacity-60, "—") maar blijven
  aanklikbaar voor de omschrijving; (2) **jsonb-dubbelcodering** gefixt in drie stores
  (`position_feature_vectors.features`, `position_tablebases.result`, `position_evals.lines` —
  schrijfpad geeft nu het map/de-lijst zelf; lezers blijven beide vormen accepteren) plus migratie
  `20261017130000` die bestaande rijen unwrapt; tests asserten `jsonb_typeof` = object/array;
  (3) **bordstabiliteit**: de kolommen-wrapper in de room-shell had na de zijbalk-verwijdering geen
  `flex-1` meer, waardoor de bordkolom de hoogte van de zettenkolom volgde en het gecentreerde bord
  bij sommige zetten 3px verschoof — geverifieerd: bordtop blijft 162px over zes zetten.
  Serieel: analysis **655**, web **280**, chess **591**, features **209**; formatter, diffcontrole.
  Let op bij deploy: de migratie draait vóór de nieuwe code; oude code crashte op ge-unwrapte rijen
  (in dev gezien) — het rollout-venster is klein maar bestaat.

- **Afgerond, klaar voor commit/deploy:** `Replace the room sidebar with a room bar and chat drawer`.
  De linkerzijbalk is weg. In plaats daarvan: een **room-bar** onder de app-header met twee rijen —
  (1) roomcode + kopieerknop, presence (avatars/follow), latency, ledenknop en rechts de
  **chatknop met ongelezen-badge**; (2) de **analyse-chips** (`analysis-chip-<id>`, horizontaal
  scrollbaar, actief gemarkeerd, hover toont detail, ster voor track/untrack, plus-knoppen voor
  nieuwe analyse/import/stelling). **Chat verhuisde naar een drawer** (`#chat-drawer`, rechts
  uitschuivend op desktop, bottom sheet op mobiel; backdrop, Escape/klik-buiten sluit; badge
  verschijnt bij berichten van anderen terwijl de drawer dicht is). De **mobiele drawer-tabs**
  (RoomTabs-hook, `data-mobile-panel`, het `@media (max-width: 859.98px)`-CSS-blok en
  `nav#room-tabs`) zijn volledig verwijderd — mobiel is nu één scrollende kolom (bord → strip →
  engine → zetten mét referentiepaneel). Bordmaat: de hoogteconstante ging van `100dvh - 14rem`
  naar `100dvh - 20rem` (de room-bar kostte ~90px verticale ruimte; bord meet nu 580px op
  1440×900 en 363px op 390×844, volledig zichtbaar). Geverifieerd in dev op desktop en mobiel:
  672→580px bord binnen de kolom, 16 chips, chat openen/sluiten met badge, drawer met log+form.
  Serieel: analysis **655**, web **280**, chess **591**, features **209**; formatter, diffcontrole.

- **Afgerond, klaar voor commit/deploy:** `Fold the book and endgame table into a reference panel`.
  Het commentaarveld onder de zettenlijst is vervangen door één **contextueel referentiepaneel**
  (zelfde plek, `#reference-panel`): openingnaam + ECO en de gespeelde corpuszetten met statistiek
  (W/D/L-balken, aanklikbaar) zolang de stelling in de corpus zit; zodra er ≤7 stukken staan schakelt
  het paneel automatisch naar de **exacte eindspeltabel** (castlingrechten uitgezonderd). Het paneel
  laadt **asynchroon** (`assign_async`, reset per stelling) — de corpusaggregatie op drukke
  openingsstellingen mag nooit een zet blokkeren; verouderde resultaten worden per key weggegooid
  (`reference_view/1` + AsyncResult). De engine-kolom is daarmee terug naar **twee tabs**
  (Engine + Features); de eerdere 'verberg Boek buiten de theorie'-regel is vervallen — het paneel
  toont de statistiek altijd en de openingnaam zolang de lijn is geclassificeerd. Commentaar
  bewerken gaat nu via een **dialoog** achter een knop in de kop van het zettenpaneel (met
  markeringsstip als het huidige knooppunt commentaar heeft; verwijderknop in de dialoog).
  Verwijderde i18n-keys: `room.bookTab`, `room.endgameTab`, `room.endgameRange` (dode keys weg).
  Geverifieerd in dev: startpositie → boekzetten (e4 3362, d4 1673 …) met openingsnamen; na 1.e4 →
  "King's Pawn Game · B00" + Siciliaan-statistiek; KQK-stelling → "White wins · Mate in 15" met
  zetten en chips; commentaardialoog openen/opslaan/verwijderen. Serieel: analysis **655**,
  web **279**, chess **591**, features **209**; formatter, diffcontrole.

- **Afgerond en gedeployed; productie gezond:** `Add the position feature readout with icon engine tabs`
  (`cd36d54`) + `Humanize the feature readout labels and values` (`b1d277b`).
  Eerste productgebruik van de features-app: de engine-kolom heeft een vierde tab **Features**
  (`Analysis.PositionFeatures.fetch_or_extract/1`, eenmalig per canonieke stelling; de vector
  wordt in `position_feature_vectors` opgeslagen — basis voor de latere gelijkeniszoektocht).
  De tab toont alle cataloguskenmerken per spec-sectie in volgorde; **labels gehumaniseerd uit de
  id's** (sectiekop draagt het voorvoegsel: `tension.queenside_tension` → "Queenside tension",
  `goals.pressure_along_file` → "Pressure along file"), **booleans als Yes/No (Ja/Nee)**,
  collecties als aantal (het label draagt het zelfstandig naamwoord; `tension.pawn_tension` → 0),
  ruwe id én ruwe waarde als tooltip, scrollbaar, met "Catalogus v0.1.0 — eenmalig berekend"-
  voetnoot. **Omschrijvingen (zelfde dag):** elk van de 371 kenmerken heeft een curated
  één-regel-omschrijving in de EN-catalogus (`features.<id>`; NL valt terug op EN tot er
  vertaald is) en een **detailstrook**: een rij aanklikken toont omschrijving + ruwe id +
  ruwe waarde (`phx-click="feature-detail"`, toggle). De scrollbalk-overlap is gefixt
  (`pr-3`), dus hoveren/toetsen werkt; een drift-test (`every catalogue feature has a
  curated description`) faalt zodra een nieuw kenmerk zonder omschrijving wordt toegevoegd.
  De leesbaarheid is deels gegenereerd (`humanize`), deels geschreven (371 omschrijvingen,
  bv. "Pawn tension — Squares attacked by pawns of both colours (contested pawn targets)").
  **Testhygiëne:** één niet-reproduceerbare flake gezien (analysis 652/655, daarna 5×
  655); de retentietest assertte op een exacte prunelijst en is nu membership-robust
  (achtergebleven kamers van een gecrashte run kunnen de lijst vervuilen).
  De tabbalk is **icoon-only** geworden (aria-label + title vertaald): vier tabs mét
  labels passen niet in de 210px-enginekolom — een gelabelde strip liet de `overflow-hidden`-kolom
  stil 23px naar links scrollen (dat knipte "Endgame" en verschoof de inhoud). Nieuwe iconen:
  cpu, book, crown, list. Geverifieerd in dev (371 kenmerken/21 secties; "Side to move → white",
  "Castling rights → KQkq", "Bishop pair both → Yes", "Pawn tension → 0"; geen overflow, geen
  verschuiving). Serieel: analysis **655**, web **277**, chess **591**, features **209**.
  Diepere semantiek (wat een aantal van 2 betekent, eenheden) vraagt later om per-kenmerk
  beschrijvingen in de catalogus; de huidige weergave is bewust generiek maar leesbaar.

- **Afgerond, klaar voor commit/deploy:** `Fix the invalid calc() classes and the mobile room layout`.
  Vijf Tailwind-klassen gebruikten `calc(...)` zonder spaties (bv. `calc(100dvh-14rem)`) — dat is
  **ongeldige CSS die de browser stil dropt**: het schaakbord viel terug op min-content (15px-vakjes,
  120px bord op mobiel; "bord klein of onzichtbaar") en ook de eval-bar-, shell- en modalhoogtes
  klopten niet. Alle vijf gefixt met de Tailwind-space-syntax `_-_` (o.a.
  `w-[min(100%,calc(100dvh_-_14rem))]`). Mobiel is de room nu een scrollende documentflow:
  bord bovenaan op volle breedte (gemeten **363px** op 390×844; engine aan: bord 315 + eval-bar),
  daaronder layers-strip, engine-tabs, tabbalk en de drawer (moves/games/chat) — geen gefixeerde
  100dvh-kolom meer die het bord tot 120px perste. Geverifieerd op 390×844 en desktop 1440×900
  (bord 576px, ongewijzigd). Nieuwe valkuil voor de docs: **Tailwind arbitrary values hebben
  underscores voor spaties; `calc()` zonder spaties is ongeldig en faalt stil** (net als de
  bestaande `-translate-*`-valkuil hieronder). Een bestaande regressietest die de oude kapotte
  klassenaam vastpinde is bijgewerkt. Serieel: analysis **655**, web **276**, chess **591**,
  features **209**; formatter, diffcontrole.

- **Bezig (interruptiegevoelig): hervatting van de bulk-import loopt** (machine `bulk-resume-2`,
  performance-2x, AMS). Wat er misging bij de eerste run: (1) de
  parallelle import deed maar **~2 partijen/s** — elke partij een eigen transactie met ~40
  position-inserts door pgbouncer op de kleine MPG-instantie (1 GB RAM; corpus groeide voorbij
  de cache) → commit- en cache-thrash; (2) de eval crashte (exit 1, vermoedelijk
  DBConnection-checkout-timeout) om 02:40 en 08:11 UTC en de machine-restartpolicy herstartte
  de opdracht vanaf 0 → elke partij faalde op een bestaand record-id (telling bevroren op
  66.237; worker vernietigd). **Fixes in `ed38319`**: grouped mode standaard (batches van 10,
  één transactie per groep), `record_id_offset` (hervatten zonder botsen/dupliceren),
  exception-vangnet (eerlijke samenvatting i.p.v.v. crash), curl-stall-detectie, `--restart no`.
  **Boekquery-fix (zelfde commit)**: covering indexes; productie-EXPLAIN van de boekquery op de
  startstelling: **8.309 ms → 516 ms**. **Hervattingsfout 2026-10-17 (opgelost):** de eerste
  hervatting gebruikte `record_id_offset: 66.237` (= aantal records) en **aboortte op de eerste
  partij na de skip-grens** (`{:import_failed, 1, :already_exists}`) — mislukte partijen
  consumeren wél een suffix, dus de juiste offset is de **hoogste bestaande suffix**, niet de
  telling. Prod-query: count 66.237, min suffix 1, **max suffix 66.253**, 16 gaten verspreid
  (13181, 19600, 32307, …) = run-1-importfouten, géén overlap voorbij de skip-grens — scenario
  "stale resume had al geschreven" uitgesloten. Gecorrigeerde run: `skip: 35.600.000`,
  `record_id_offset: 66.253`, zelfde prefix; eerst ~75 min skip-scan (~8,2k games/s), daarna
  ~100k resterende partijen. Oude `bulk-resume`-machine vernietigd. Voortgang via `flyctl logs`
  (`bulk import progress` met handed=). Bij een crash: nieuwe run met skip = vorige read, offset
  = max suffix (niet de telling). Mijn eigen fouten hier: ETA op scanrate i.p.v. importrate, de
  restart-policy niet uitgezet, en de offset op de telling i.p.v. de max-suffix gebaseerd.

- **Afgerond, klaar voor commit/deploy:** `Add streaming bulk corpus import for lichess dumps`.
  `Analysis.BulkImport`: `curl | zstd -dc` → FIFO (echte backpressure, begrensd geheugen),
  header-filter vóór het parsen (beide ratings ≥ drempel, geen bullet), daarna
  `PgnBatchImporter.import_stream_parallel/4` (transactie per partij, fouten stoppen de run
  niet), bronstatus via statusbestand (afgebroken download wordt eerlijk gemeld), `:skip`
  (hervatten) en `:limit` (vroegtijdig sluiten). Draait vanaf dev (`mix run`) én vanaf een
  releasemachine (`bin/openchesslab eval …`, start zelf de apps). Dockerfile: `curl` + `zstd`
  in de runtime-image. Gemeten op dev met échte dumps (zie development-history): 2026-09 tot
  100k partijen → 1,66% kept bij 2200+, 0,187% bij 2500+, 0 fouten; scan ~11,5k partijen/s;
  **≈56 KB opslag per canonieke partij** (position_features-GIN alleen al ~27%). Consequentie:
  één 2500+-maand ≈ 9,5 GB, één 2200+-maand ≈ 84 GB; de 10M-partijenambitie ≈ 560 GB
  (+~$157/mnd) zonder optimalisatie. Besluit gebruiker: **pilot = één 2500+-maand van 2026-09
  op een 30 GB-schijf** (opwaarderen via Fly-dashboard, +~$6/mnd). Vervolg: deployen, schijf
  opwaarderen, tijdelijke worker-machine in AMS (`shared-cpu`, 8 workers) draaien, samenvatting
  + boekverificatie in productie. Bekende datacaveat: games vóór ~2014 kunnen
  van-vak-disambiguatie (`Rc8c6`) bevatten → `:invalid_game`-fouten (12% in 2013; 0% modern).
  Serieel groen: analysis **654**, web **276**, chess **591**, features **209**; formatter,
  diffcontrole. Nieuwe tests: `bulk_import_test.exs` (filter, skip, limit, run/1 tegen de
  echte corpus).

- **Afgerond en door mij gedeployed; productie gezond:** `Add the endgame table tab with lichess
  tablebase results` (`305d128`), bovenop `58cd927`. Nieuwe derde tab in het engine-paneel
  (Engine/Boek/Eindspel):
  exacte 3–7-stukken-uitslagen via de publieke lichess-tablebase-API (`Web.Tablebase`,
  `tablebase.lichess.ovh`, gratis, geen sleutel, dezelfde dienst die lichess zelf gebruikt),
  permanent gecachet per canonieke stelling in `position_tablebases` (`Analysis.PositionTablebases`,
  migratie `20261016190000`) — één externe aanvraag per unieke stelling, ooit. Stellingen met
  castlingrechten worden overgeslagen; >7 stukken toont uitleg zónder aanvraag; categorieën
  worden vanuit het perspectief van de zetkleur naar kleurtermen vertaald (incl. 50-zettenregel-
  uitzonderingen met *-voetnoot); zetten zijn aanklikbaar. Privacy: FEN's van opgezochte stellingen
  gaan naar lichess (standen, geen gebruikersdata). Serieel groen: analysis **649**, web **276**,
  chess **591**, features **209**; formatter en diffcontrole. Browsergverifieerd op dev met een KQ-K-
  stelling: "Wit wint · Mat in 15" → na Qd5 "Zwart verliest · Wordt mat in 14", echte API-data.
  Nieuwe tests: `position_tablebases_test.exs` (opslaan/lezen/opruimen) en drie webtests
  (echte fetch via stub + cache, bereikboodschap zonder fetch, onbereikbaar eerlijk gemeld).
  architecture.md, AGENTS.md (verouderde "grants/import planned"-regels bijgewerkt) en HANDOFF
  bijgewerkt.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Prune populated rooms after 3 days of inactivity` (`7b6635e`), bovenop `2b9e095`.
  Deploy-notitie: Fly gaf twee keer een tijdelijke bolt-tokenfout; derde poging lukte,
  geverifieerd dat er weer exact één machine draait (de tussentijdse verdubbeling is opgeruimd). Productbeslissing 2026-10-16 (periode én basis door de
  gebruiker gekozen): 3 dagen zonder activiteit (bezoek, zet, commentaar of chat resetten de
  klok via `rooms.last_active_at`). De pruner (`RoomPruner`, alleen productie, dagelijks)
  verwijdert nu ook gevulde kamers mét hun kameranalyses; bibliotheekverwijzingen worden eerst
  gematerialiseerd (klonen via de codec — het binaire record bevat het analyse-id, een
  SQL-kopie corrupteert dat — en entries wijzen naar de kopie). Canonieke partijen/posities
  blijven (gedeelde corpus). De 30-daagse lege-kamerregel blijft bestaan. AGENTS.md en
  architecture.md bijgewerkt. Serieel: analysis **646**, web **273**, chess **591**, features
  **209**; formatter, assetbuild, diffcontrole. Nieuwe tests: `room_retention_test.exs`
  (pruning, materialisatie, touch) + touch-bij-bezoek in de websuite. Te verifiëren op
  productie door de gebruiker: na de eerste dagelijkse run zou geen actieve kamer mogen
  verdwijnen; pruningslogboek via `flyctl logs` ("Pruned N inactive rooms").

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Add opt-in Lichess library sync` (`f3105ab`), bovenop `158658b` (plus daarvoor `Format the analysis importer with Quokka` — het
  formatter-restje dat al de hele sessie dirty was). Feature-slice 2026-10-16 (opt-in en
  bibliotheek-bestemming waren expliciete gebruikersbeslissingen): de accountmodal kreeg een
  toggle onder een gekoppeld Lichess-account; `provider_grants` kreeg
  sync_enabled/sync_cursor/synced_at; `Web.LichessSync` pagineert vooruit met
  `sort=dateAsc&pgnInJson=true` en importeert via nieuwe `Analysis.LibraryImport`
  (canonieke record + geannoteerde analyse + bibliotheekentry "White – Black 1-0 (2026)");
  worker in de web-supervisieboom (15 min + kick bij aanzetten; uit in tests). 401 → grant
  weg + uit. Suite-instabiliteit onderweg opgelost: de corpus-zoektest bleek te flakelen
  zodra eerdere tests canonieke partijen achterlieten — structurele zoekmodi gebruiken
  match_all-recordpredicaten, dus pagina 1 vult met oudere occurrences. De test truncate nu
  zelf de corpustabellen vóór seeden (hij is async: false), en assert op de geretourneerde
  html-strings (has_element? las een verouderde proxy-tree). Verwijderd: de verouderde
  "Lichess-import komt later"-notitie uit de accountmodal + sleutel. Serieel: analysis **643**,
  web **272** (ook op seeds 42/1/12345/999999/7), chess **591**, features **209**; formatter,
  assetbuild, diffcontrole. Browsertest: toggle zichtbaar en uit-by-default onder het
  gekoppelde account.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Discard the review when switching analyses` (`737edac`), bovenop `db90bae`. Bugrapport 2026-10-16: een lopende review ging na het wisselen
  van partij verder vanaf de oude ply op de nieuwe partij. Oorzaak: `engine_review` overleefde
  de analysewissel; de revisiecheck dekt alleen bewerkingen binnen één analyse. Fix in
  `set_analysis`: bij elke analyse-id-wijziging (geladen struct als ground truth —
  `handle_params` overschrijft `selected_analysis_id` vóór het laden!) wordt de review
  verworpen, lopend én klaar (de klaar-variant lekte net zo goed: marks/accuracy van partij A
  op partij B). Opnieuw reviewen is één klik. Serieel: web **268** (2 nieuwe regressietests),
  formatter, assetbuild, diffcontrole. Browsertest: review op partij B gestart, gewisseld naar
  A — geen voortgang, geen annuleerknop, wel een verse reviewknop.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Remove 120 dead i18n keys` (`6ec8f0d`), bovenop de accuracy-deploy (`2a5486a`). Hygiene 2026-10-16: de catalogi bevatten 491 sleutels waarvan er 120
  nergens (meer) gebruikt werden — overblijfselen van eerdere iteraties van de bibliotheek
  (`personal.*`), import, zoeken, engine-status, shortcuts en laag-legenda
  (`room.legendWhiteAttacks` c.s.). Verwijderd na een scan die letterlijke usages, plural-
  basissleutels en dynamisch gebouwde families (`theme.`, `shapeColor.`, `room.skip.`,
  `room.provider.`) uitsluit; beide catalogi verwijderen exact dezelfde 120 sleutels
  (assert op drift). `I18n.t` valt bij een missende sleutel terug op de sleutel zelf —
  die zou als rauwe tekst zichtbaar zijn; browsertest in NL toont dat nergens. Serieel:
  web **266**, assetbuild, diffcontrole.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Show per-side accuracy after a game review` (`2a5486a`), bovenop `a71b20d`. Feature-slice 2026-10-16: na een review toont de samenvatting nu
  nauwkeurigheid per kleur ("Nauwkeurigheid: wit 86% · zwart 14%"). Implementatie volgt
  lichess' gepubliceerde model (lichess.org/page/accuracy + lila AccuracyPercent.scala, opnieuw
  geïmplementeerd in `Web.Accuracy`): per zet accuracy via de gefitte exponentiële curve op de
  Win%-daling (+1 onzekerheidsbonus, geclampt), per partij het gemiddelde van de
  volatiliteitsgewogen en harmonische gemiddelden per kleur; gewichten uit standaarddeviatie
  van Win%-vensters (2–8, geclampt 0.5–12). Aangestuurd vanuit `classify_review` met de echte
  startzijde. Serieel: web **266** (8 nieuwe Accuracy-tests + reviewflow-assertie); formatter,
  assetbuild, diffcontrole. Browsertest: scholar's-mate-lijn geeft wit 86% / zwart 14% met de
  Ke7 ?? als kritiek moment.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Store encrypted Lichess grants and import the linked account's games` (`16bb06d`),
  bovenop `371fef3`. Secret `PROVIDER_GRANT_KEY` is gezet vóór de deploy (waarde alleen in Fly). Feature-slice 2026-10-16 (gepland
  werk uit AGENTS.md): de Lichess-token werd tot nu toe direct na verificatie ingetrokken —
  nu wordt hij bewaard als versleutelde grant (`provider_grants`, AES-256-GCM onder een eigen
  `PROVIDER_GRANT_KEY`; runtime vereist, dev/test hebben vaste sleutels). Behalve
  gebruikersnaamloos importeren ("Import my games" op de Lichess-tab via `/api/account` →
  bestaande publieke fetch) verandert de privacycontracten: retentie i.p.v. revocatie,
  gedocumenteerd in lichess_oauth, architecture.md en deze handoff. Grants verdwijnen bij
  unlink, accountverwijdering (cascade) en een 401 van Lichess; opslag mag login nooit
  breken (rescue + waarschuwing). Achtergrond-sync blijft toekomstig werk. Serieel: analysis
  **640**, web **258** (nieuw: grant-roundtrip/tamper/cascade, callback slaat grant op, mijn-
  partijen-flow met stubs, 401 verwijdert de grant, unlink ruimt op); formatter, diffcontrole.
  Browsertest: blok zichtbaar met grant, echte 401 → eerlijke fout + grant weg.
  Deployvolgorde: eerst `flyctl secrets set PROVIDER_GRANT_KEY=...`, dán deployen.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Align catalogue outposts with the standard definition` (`371fef3`), bovenop `2df0d3f`. Opruimen van de gisteren gemelde divergentie: de
  features-catalogus had eigen zwakkere outpostimplementaties (knight/bishop +
  vijandelijke-helft + alleen huidige pionaanval). Nu één gedeelde
  `Features.Catalogue.Support.outpost_square?/3` met de Wikipedia-definitie (pion-gedekt,
  4e–7e rij, geen vijandelijke pion kan het ooit bereiken), gebruikt door
  `goals.establish_outpost`, `placement.knight_outpost`, `quality.knight_outpost` en
  `squares.outpost`/`occupied_outpost`; `squares.potential_outpost` gebruikt dezelfde
  permanente-gatentest zonder dekkingsvereiste. Semantiek verandert onder dezelfde
  feature-namen — bedoeld. Bestaande fixtures bleven groen (echte outposts); nieuwe tests
  dekken de 4e-rij en de "pion kan later nog aanvallen"-uitsluiting. Serieel: features
  **209**, analysis **635**; formatter, diffcontrole.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Import multiple games from PGN, Lichess and Chess.com` (`d598623`), bovenop de
  sessienaam-deploy (`8fe2037` + record). Feature-slice 2026-10-16 (gebruiker
  afwezig; eigen beslissingen gedocumenteerd): het importdialoog is nu echt — de mock
  Lichess/Chess.com-tabs en demo-sleutels zijn weg. Blunderfest-stijl: het plakveld accepteert
  gemengd PGN (meerdere partijen) + lichess.org-partijlinks (één per regel); Chess.com-links
  krijgen een eerlijke skip (geen publieke per-partij-API). Nieuw: `Web.GameImport`
  (classificatie + fetches, User-Agent vereist — Lichess 404t anders! — httpc met
  `Application.get_env(:web, :game_import_request)`-testnaad) en
  `PgnBatchImporter.split_games/1` (gedeelde splitter; elk deel van de gemengde box splitst
  apart). Lichess-tab: gebruikersnaam → recente N partijen via `/api/games/user`; Chess.com-tab:
  via het publieke maandarchief (`api.chess.com`, nieuwste N). Partiële import toont skips in
  de open dialoog; alleen totale mislukking is een fout. Provider grants/OAuth-import blijft
  aparte toekomstige stap. Serieel: web **257**, analysis **635**, chess **591**; formatter,
  diffcontrole. Browser-end-to-end tegen de echte Lichess-API: gemengde box (PGN + URL) 2
  partijen erbij, gebruikersnaam-import 2 partijen erbij. architecture.md bijgewerkt.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Give every browser session one display name` (`8fe2037`), bovenop `ccf6952`. Productbeslissing 2026-10-16: meerdere identiteiten
  (accountlabel vs. kamerlabel) verwarren; de stabiele accountidentiteit verdwijnt. Nu: een
  nieuwe `Web.SessionName`-plug genereert bij het eerste bezoek een naam in de sessie —
  die naam geldt voor gast én ingelogde gebruiker, in presence, chat en het accountmenu
  (badge + dropdown + helptekst aangepast). `DisplayName.for_user/1` en `for_room/2` zijn weg;
  lidmaatschapslabels in private kamers zijn weer per-lidmaatschap willekeurig (duurzaam
  beheerlabel, bewust géén accountidentiteit) en presence gebruikt overal de sessienaam
  (de member-override en `Rooms.member_display_name/2` zijn verwijderd). De identiteit leeft
  in de sessie, niets nieuws in de DB. Meer ontwerp volgt in een later stadium. Serieel:
  analysis **634**, web **243**, chess **591**; formatter, assetbuild, diffcontrole.
  Browsertest: accountbadge == presencebadge ("Kind Gecko 59"), stabiel over reloads, ook voor
  gasten. NB: de outpost-fixtures in de analysis-integratietests zijn aangepast aan de
  gecorrigeerde outpostdefinitie (SQL-extractie deelt `PositionProperties.outposts/1`).

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Make room names per-room pseudonyms for signed-in users` (`de1df1a`), bovenop `b4b3626`. Privacy-beslissing 2026-10-16: het
  stabiele accountlabel in elke kamer tonen maakt gebruikers kamer-overstijgend herkenbaar.
  Nu `DisplayName.for_room(user_id, room_code)` (sha256 over kamercode + user-id): in elke
  kamer een stabiel maar anders pseudoniem; het accountmenu behoudt `for_user/1` (alleen voor
  de gebruiker zelf zichtbaar). Alle toewijzingspaden gebruiken het: presence in publieke
  kamers, lidmaatschapslabels bij aanmaken/invite/bibliotheek (de labelberekening verplaatst
  naar ná de kamercode-generatie in `home_live` en `shell_panels`). Gasten houden
  willekeurige namen; bestaande opgeslagen lidlabels blijven. Serieel: web **244**,
  formatter, assetbuild, diffcontrole. Browsertest: UIUX01 stabiel "Calm Lynx 96" over
  reloads, nieuwe kamer "Keen Wolf 32", accountmenu "Mighty Panda 41".

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Use the stable account label as the room name for signed-in users` (`7a998e6`), bovenop
  `c97a0b7`. Bugrapport 2026-10-16: een ingelogde
  gebruiker heette "Keen Beaver 72" in de kamer maar "Lively Ferret 81" in het accountmenu —
  kamerpresence gebruikte per-mount willekeurige namen. Nu krijgt een ingelogde gebruiker
  overal het stabiele accountlabel (`DisplayName.for_user/1`): kamerpresence (publieke kamers),
  het opgeslagen lidmaatschapslabel bij kamer-aanmaken, invite-accepteren en bibliotheek-openen.
  Bestaande lidmaatschapslabels blijven ongewijzigd (duurzaam); gasten houden willekeurige
  namen. Privacy-notitie: het label is pseudoniem maar nu wel kamer-overstijgend herkenbaar —
  bewuste afweging (dit was de eerder uitgesplitste presence-unificatie). Ook: twee
  ongebruikte opponent-half-maskers uit `PositionProperties` weg (waarschuwing uit de
  outpostslic). Serieel: chess **591**, web **243**; formatter, assetbuild, diffcontrole.
  Browsertest: presence-badge "MP · Mighty Panda 41" == accountbadge.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Fix outpost detection to the standard definition` (`9d10658`), bovenop `80171f5`. Bugrapport 2026-10-16: de outpostlaag markeerde
  elke pion-gedekte paard in de vijandelijke helft. Nu de Wikipedia-definitie: het VELD is de
  outpost — pion-gedekt, op de 4e–7e rij (vanuit de eigen kleur), en geen vijandelijke pion kan
  het ooit bereiken (ook niet "later": pionnen op aangrenzende lijnen die nog niet voorbij zijn
  diskwalificeren). Bezetting door een stuk is niet vereist; lege outpostvelden worden ook
  getoond. Bestaande bitboardtests encodeerden de oude definitie; verwachtingen bijgewerkt met
  per veld herleide controles. NL-label is nu "Outposts" (gebruikerswens: in het Nederlands is
  "outpost" ook gangbaar). Serieel: chess **591**, web **242**; formatter, assetbuild,
  diffcontrole. Browsertest: beginstelling toont 0 ringen; NL-labels kloppen.
  Let op: de features-catalogus (`goals.ex`, `placement.ex`) heeft een eigen, zwakkere
  outpostdefinitie (knight + huidige pionaanval) — bewust buiten scope gelaten; eventueel later
  alignen.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Split the attacks layer into coverage and defended-pieces layers` (`6eeb80e`), bovenop
  `46d7ce8`. UX-bespreking 2026-10-16: de
  aanvalslaag telde ook eigen bezet velden mee ("verdedigd"), waardoor de beginstelling
  onleesbaar oplichtte. Beslissing van de gebruiker: twee aparte lagen. Semantiek in
  `Chess.PositionProperties` aangepast: `attacked_squares/1` = dekking (leeg of vijandig bezet,
  eigen bezetting gemaskeerd); nieuwe `defended_squares/1` = eigen stukken die de eigen kleur
  dekt (disjuncte verzamelingen, getest). De boardlaag "Attacked squares" toont nu alleen
  dekking (beginstelling = exact de 3e/6e rij-frontier); nieuwe laag "Defended pieces" markeert
  verdedigde eigen stukken met een hoekpunt in de kleur van de verdediger. Features-catalogus
  onaangeroerd (eigen implementatie). Serieel: chess **587**, web **240**; formatter,
  assetbuild, diffcontrole. Browsertest: beide lagen op de beginstelling gecontroleerd
  (frontier + hoekpunten; torens terecht onverdedigd).

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Swallow board shortcuts while a dialog is open` (`59f9161`), bovenop `8dbb337`. Bugrapport 2026-10-15: met de sneltoetsenpopup open
  lekten toetsen naar de app eronder (F draaide het bord, pijlen stapten door de partij).
  Beide keydown-handlers (AppUI op document, Board op het bord) stoppen nu zodra er een
  `[aria-modal='true']` in de DOM staat; Escape blijft de dialoog sluiten en de rondleiding
  behoudt zijn pijltjesnavigatie. Serieel: web **239**, formatter, assetbuild, diffcontrole.
  Browsertest: F/pijlen dood onder de popup, na Escape werkt F weer; tourpijlen en Escape
  ongewijzigd.

- **Afgerond en door mij gedeployed; productie gezond:** `Style shortcut keys as
  physical keycaps` (`8dbb337`), bovenop `c1d5752`. UX-verzoek 2026-10-15: `<kbd>`-toetsen moeten eruitzien als
  fysieke toetsen. Eén globale `kbd`-regel in `@layer base` (app.css): verhoogd vlak
  (`--panel-hover`), rand `--border-strong`, dikkere onderrand (2px) als drukkant, afgeronde
  hoeken, `--foreground`-tekst — thematokens, dus licht én donker kloppen. Serieel: web **239**,
  formatter, assetbuild, diffcontrole. Browsertest: screenshots licht + donker gecontroleerd.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Widen the shortcuts dialog and use kbd elements for keys` (`8975ea5`), bovenop `da20157`. UX-feedback 2026-10-15: de sneltoetsenpopup was te
  smal ("Vorige / volgende zet · Shift + ← / →" brak over twee regels). Nu `max-w-2xl` +
  niet-brekende toetsencellen (`whitespace-nowrap shrink-0`); rijen via een gedeelde
  `shortcut_row`-component. Toetsen zijn nu semantische `<kbd>`-elementen (er was geen reden om
  het niet te doen — alleen het element is veranderd, de stijl niet). Serieel: web **239**,
  formatter, assetbuild, diffcontrole. Browsertest (NL): geen omgeslagen toetscellen meer.

- **Afgerond en door mij gedeployed; productie gezond:** `Unify engine tabs with the strip
  style and move engine controls into the tab content` (`da20157`), bovenop `385c522`. UX-feedback
  2026-10-15: (1) de actieve ENGINE/BOEK-tab week af (grijze pill) van de
  MATERIAAL/RUIMTE/LAGEN-tabs (cyan + ononderstreping) — beide gebruiken nu één gedeelde
  `tab_class/2` (hernoemd van `strip_tab_class/2`); (2) het instellingentandwiel en de
  engine-aan/uit-schakelaar stonden in de tabbalk — ze zitten nu in een werkbalk bovenaan de
  ENGINE-tabinhoud; het instellingenpopover opent er direct onder (`top-[5.5rem] right-3`,
  nog steeds verankerd aan `#engine-panel` zodat `overflow-hidden` niet clipt). Serieel: web
  **239**, formatter, assetbuild, diffcontrole. Browsertest: tabstijlen identiek aan de strip,
  popover-positionering en boek-tab gecontroleerd.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Turn the guided tour into a spotlight walkthrough` (`f37c8e0`), bovenop `08aaac0`. Productklacht 2026-10-15: de "rondleiding" was een
  popup met feature-uitleg. Nu: elke stap highlight zijn `data-tour`-anker (bord, analyses,
  zetten, engine, import, zoeken, help) met een accentring + een blur-achtergrond met uitsparing
  (clip-path-gat), en de uitlegkaart wordt per stap naast het element gepositioneerd door een
  `GuidedTour`-hook (fallback: gecentreerd als het anker ontbreekt/verborgen is). Achtergrond
  matched de andere popups (`backdrop-blur-xs backdrop-saturate-[.9]`, geen donkere laag).
  Valkuil gedocumenteerd: Tailwind v4 gebruikt de CSS-`translate`-property — inline
  `transform:none` alleen werkt niet, `style.translate` moet mee. Serieel: web **239**
  (3 nieuwe tourtests), formatter, root-compile, assetbuild, diffcontrole. Browsertest: alle
  7 stappen zonder overlap, kaart altijd in viewport; screenshots gecontroleerd.
  NB: werkboom bevatte een niet-gerelateerde formatterwijziging in
  `apps/analysis/lib/analysis/pgn_analysis_importer.ex` (Quokka-aliasvolgorde) — buiten deze
  commit gelaten.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond:**
  `Show a stable identity badge and name in the account menu`, bovenop `7f14d7d`. Productbeslissing 2026-10-15: gegenereerde namen waren
  per-mount — niet herkenbaar. Nu: `DisplayName.for_user/1` (deterministisch uit het interne
  user-id via sha256 over dezelfde woordenlijsten), `name_color/1` (hsl-hue uit de naamhash,
  vast S/L, witte initialen), `initials/1` (gedeeld met de room-presence). De accountknop toont
  de initialen-badge; het dropdownmenu opent met avatar + volledige naam + "Ingelogd" + een
  hulp-icoon dat het gegenereerde label uitlegt. Volledig serieel: web **236** (seed 511632);
  formatter, root-compile, assetbuild, diffcontrole geslaagd. Browsertest: badge MP groen,
  dropdown toont "Mighty Panda 41 · Ingelogd" + hulptekst. Room-presence behoudt per-mount namen;
  unificatie is een aparte beslissing.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie gezond (health/ready
  200):** `Debounce the position URL sync and skip redundant patch loads`, bovenop `74e2d75`. Gebruikersbug: pijltje ingedrukt houden → URL
  accumuleerde ",0" maar het scherm bevroor tot de burst eindigde. Root cause (live.js):
  elke push_patch zet een pendingLink; terwijl die open staat buffert `update()` alle render-diffs
  (`view.ts`) — een patch per toets = continue pending link = bevroren scherm. Fix: select_path
  pusht niet meer per navigatie; een idempotente `Process.send_after`-timer (300 ms) synct de URL
  zodra de navigatie tot rust komt, en `handle_params` slaat het herladen over als de patch met de
  huidige staat overeenkomt. Volledig serieel: web **233**, analysis **634**, chess **584**;
  formatter en diffcontrole geslaagd. Browserverificatie van held-key volgt zodra de
  Playwright-MCP weer verbonden is (playwright server crashte; herstel via /mcps), of de
  gebruiker verifieert handmatig op productie: pijltje ingedrukt houden in een 51-zetten partij
  moet nu continu tracken met de URL die na het loslaten eenmalig synchroniseert.

- **Afgerond en door mij gedeployed (deployvrijheid gegeven); productie geverifieerd:**
  `Add the opening book tab with ECO classification and corpus move stats`, bovenop `bbd542d`.
  Engine-kolom krijgt tabs Engine|Book. Vendored CC0 lichess-org/chess-openings (TSV's onder
  apps/database/priv/openings) → migratie `20261015170000` seedt `openings` (position_record,
  eco, name) door elke PGN-lijn met onze eigen regels te replayen; `game_occurrences.move`
  (migratie `20261015173000`) wordt bij import gevuld + `GameStore.backfill_occurrence_moves/0`
  repareert oudere rijen. `Analysis.OpeningBook`: classify (exacte stelling), classify_line
  (diepste match langs de lijn), moves (aantallen per zet + W/D/L per record + opening na de
  zet). Tab toont de huidige opening en klikbare zetten met aantallen en W/D/L-balken; spelen
  werkt via Analyses.play. Nieuw in chess: `Notation.UCI.format/1`. database-app dep op chess
  toegevoegd (migratie-seed). Volledig serieel: chess **584**, analysis **633-634** (één run
  raakte de bekende `:invalid_occurrences`-suiteflake — nu ook waargenomen in
  PgnAnalysisImporterTest; gedocumenteerde backlog, mechanisme: concurrente import + truncate),
  web **233**; formatter, root-compile --warnings-as-errors, assetbuild, diffcontrole geslaagd.
  Browsertest: tab met e4/d4/Nf3 aantallen + openingsnamen, klik speelt, classificatie volgt
  de lijn (King's Pawn Game B00 → C20). Productie: 3865 openings geseed via release-migratie;
  backfill was een no-op (0) want de productiecorpus is nog leeg — het boek vult zodra partijen
  geïmporteerd worden (room-play maakt geen canonieke partijen). Live geverifieerd: eerlijke
  lege toestand op startpositie, King's Pawn Game B00 na 1.e4.

- **Afgerond en door mij gedeployed (gebruiker gaf deployvrijheid vanaf 2026-10-15);
  productie-stresstest geverifieerd:**
  `Speed up the move list and cancel reviews when the tree changes`, bovenop `117b32e`.
  (1) `PositionStore.get_many/1` + preload in `AnalysisView.move_list_data`: de zettenlijst
  laadt alle posities in één query i.p.v. één per zet — de resterende PV-kliklag bij 40+ zetten.
  (2) Mid-review een zet spelen cancellde de review voorheen NIET (het resultaat werd stilletjes
  gedropt op revisiemismatch → eeuwige "Reviewing…"); nu eerlijke cancel met melding, en de hook
  keert terug naar interactief. Volledig serieel: analysis **630**, web **232**; formatter,
  assetbuild, diffcontrole geslaagd. Stresstest op productie (NL↔AMS): zetten met engine aan
  ~170-220 ms; engine aan 170 ms (cache); diepe PV-klik met 28-zettenlijst 312 ms (was ~1 s);
  toggle uit 387 ms (was 1627 ms); review doorloopt 29 posities in ~2-3 s en mid-review edit
  cancellt eerlijk zonder hang.

- **Afgerond, gecommit en gepusht; deploy volgt door gebruiker:** `Batch engine-line insertion
  and lighten engine updates`, bovenop `d4d839a`. Productie-lag (NL↔AMS): (1) `Analyses.
  play_line/3` — een hele engine-lijn in één transactie (één revisiebump, één broadcast) i.p.v.
  N× play/3; gedeelde `play_unpersisted` met play/3. (2) `engine-update` werd per 250ms-PV-pars
  lichter: geparsde lijnen gecachet op pv-string (`engine_pv_cache`, per positie leeggemaakt),
  en lijnen tonen max 8 zetten + "…" (volledige UCI blijft voor play). Volledig serieel: analysis
  **630**, web **231**; formatter, assetbuild, diffcontrole. Browsertest: diepe PV-klik 120 ms
  lokaal (was ~1 s), 8 zetten + ellipsis per lijn.

- **Afgerond, gecommit, gepusht en door gebruiker gedeployed (bevestigd 2026-10-15):**
  `Cache all computed lines and honor engine settings over the cache` (+ HANDOFF-record
  `f540852`), bovenop `f540852`. Gebruikersbug: instellingen wijzigen
  deed niets meer — de cache-skip keek alleen naar fen+diepte, blind voor MultiPV, en de cache
  bevatte sowieso maar één lijn. Nu: `position_evals` krijgt `multipv` + `lines` (jsonb,
  migratie `20261015160000` met backfill), de skip vereist dekking op beide assen, het paneel
  toont de eerste N gevraagde lijnen van de volledige set (render-time take, geen destructief
  snijden), en de review persist blijft 1-lijn. Volledig serieel: analysis **628**, web **231**;
  formatter, assetbuild, diffcontrole geslaagd. Browsertest: lijnen 3→2→3 direct uit cache.

- **Afgerond, gecommit en gepusht; deploy volgt door gebruiker:** `Keep the evaluation bar
  visible while the engine computes`, bovenop `7233565`. De evaluatiebalk rendeert nu zodra de
  engine aan staat (niet pas bij de eerste evaluatie) en toont neutraal gedimd "—" tijdens
  compute; het bord reserveert de balkruimte altijd bij engine-aan, dus geen layoutshift of
  flicker meer bij PV-klik of bordzet. Tests: 54 gericht, volledig web **230** (seed 511632);
  browsertest: MutationObserver zag de balk nooit verdwijnen tijdens PV-play en bordzetten.

- **Afgerond, gecommit en gepusht; deploy volgt door gebruiker (samen met de kolom-slice
  `1f004db`, nog niet gedeployed):** `Keep the engine panel stable and honest during play`,
  bovenop `1f004db`. Twee vervolgfixes: (1) de PV-lijst is nu een begrensd, intern scrollend
  gebied (`flex-1 overflow-y-auto`) zodat grafiek en review niet meer verspringen terwijl lijnen
  verdiepen; (2) na een zet of navigatie toont het paneel nooit meer een stale evaluatie —
  `set_analysis` ververst de enginepositie: cachehit vult direct (de hook slaat compute over),
  anders eerlijke "Analyzing…"-toestand tot de eerste verse update (ook de reden dat "de engine
  lijkt niet te analyseren": het oude resultaat bleef zichtbaar). room.engineLoading hernoemd
  naar Analyzing/Analyseren. Volledig serieel: web **230 geslaagd** (seed 511632); formatter,
  root-compile, assetbuild, diffcontrole geslaagd. Browsertest: grafiek stabiel tijdens verdieping.

- **Afgerond, gecommit en gepusht; deploy volgt door gebruiker:** `Move the engine panel into its
  own column beside the board`, bovenop `d0e6f36`. Layoutwijziging (productbeslissing 2026-10-15):
  de engine-inhoud (toggle, settings, stats, grafiek, review, PV-lijnen, peek) verhuist van de
  rechterzijbalk naar een eigen vol-hoogte kolom tussen bord en zijbalk (210px, 180px ≤1100px,
  gestapeld vóór de zetten op mobiel). De zijbalk houdt zetten + commentaar over; de commentaarbox
  is weer in beeld. PV-lijnen wrappen nu echt (flex-wrap; HEEx laat geen whitespace tussen
  for-comprehension-spans, dus inline-flow brak niet). Tourtekst bijgewerkt. Volledig serieel: web
  **228 geslaagd** (seed 511632); formatter, root-compile --warnings-as-errors, assetbuild,
  diffcontrole geslaagd. Browsertests: desktop (commentaar zichtbaar zonder scrollen, lijnen
  wrappen binnen de kolom) en mobiel 430px (sectie stapelt na de strip).

- **Afgerond, gecommit en gepusht; deploy volgt door gebruiker:** `Import annotated PGN
  variations into the analysis tree`, bovenop `8f31baf`. `PgnAnalysisImporter` parseert nu het
  volledige movetext als boom: een variatie na een zet is een alternatief voor die zet (sibling
  van het hoofdlijkind), willekeurig diep genest, met opmerkingen/NAG's op de juiste knopen en
  posities via legale-zettenreplay in de canonieke position store. Hoofdlijn blijft uit de
  game-record-tree geannoteerd; voorloopcommentaar hoort bij de root. Verifieert: ongebalanceerde/
  ongesloten variaties, variatie zonder voorgaande zet, illegale variatiezetten en NAG-regels
  falen de import atoomair (record + analyse committen of rollbacken samen). Canonieke partij
  blijft hoofdlijn-only. Volledig serieel: analysis **627**, web **228**; formatter, root-compile
  --warnings-as-errors, diffcontrole geslaagd. Browsertest op dev: geneste genoteerde PGN importeert
  met alle takken en opmerkingen zichtbaar in de zettenlijst.

- **Afgerond, gecommit, gepusht en door gebruiker gedeployed (bevestigd 2026-10-15):**
  `Persist engine evaluations per canonical position`, bovenop `abf39ad`. Nieuwe tabel `position_evals` (migratie
  `20261015140000`, pk position_id+engine, FK cascade) + `Analysis.PositionEvals` (get,
  get_many, deepest-wins upsert). Toggle aan: cachehit vult paneel + balk + arrow + grafiek
  direct; de hook slaat de worker over zolang de cachede diepte ≥ de gevraagde diepte is
  (dieper instellen herstart gewoon). Persist op `bestmove` (hook markeert final; een pending
  throttle-flush wordt dan eerst afgebroken) en per review-positie op diepte 12. Evals zijn
  wit-relatief opgeslagen, engine-geversioneerd, volgen transposities via canonieke ids.
  engineNote-tekst geeft nu eerlijk aan dat resultaten gedeeld worden. Volledig serieel:
  analysis **626**, web **228**, chess onveranderd groen; root-compile --warnings-as-errors
  (per-app compile in apps/web waarschuwt vals-positief op sibling-volgorde; root is canoniek).
  Browsertest: eerste compute diepte 14, daarna toggle uit/aan → eval in 824 ms zonder
  laadstatus, data-cached-depth=14.

- **Afgerond, gecommit, gepusht en door gebruiker gedeployed (bevestigd 2026-10-15):**
  `Add structural position search modes to game search` (+ architectuur-notitie `a0ac76d`),
  bovenop `3427bdf`. De position-mode-selectie is terug, nu echt: exacte
  stelling (`equivalent/1`), zelfde pionnenstructuur (`pawn_structure/1`), of elke symmetrie
  (`pawn_structure_symmetries/1` — exact + kleurverwisseling + lijnspiegeling + combinatie).
  Alleen zichtbaar zodra er een FEN staat. Web-test met een extra transpositie-partij bewijst de
  discriminatie; browsertest op dev bevestigt exact/structuur/symmetrie (de d4-d5-partij matcht
  als lijngespiegde symmetrie). Volledig serieel: web **226 geslaagd** (seed 511632);
  formatter en diffcontrole geslaagd.

- **Afgerond, gecommit, gepusht en door gebruiker gedeployed (bevestigd 2026-10-15):**
  `Wire game search to the real corpus queries`, bovenop `3130242`. De zoekmodal draait nu echt op `GameSearch.page/3`:
  spelersnaam (case-insensitive ILIKE-substring, nieuwe `GameRecordQuery.metadata_value_contains/2`
  + `all/1`/`any/1`-juncties), kleur, resultaat (exacte JSONB-containment) en exacte stelling via
  `PositionQuery.equivalent/1` (de demo-FEN deed voorheen helemaal niets). Keyset-paging met
  "Toon meer", één rij per record (dedupe), ongeldige FEN is een eerlijke fout, ⌖-knop vult de
  bordstelling. Hit openen = `Analyses.create_from_game_record/2` in de room. Demovelden opening/
  datum/mode/substitutions verwijderd; de import-modal providermock blijft bewust demo.
  Gericht: game_search 13 incl. nieuwe combinatietest; volledig serieel: analysis **623**,
  web **226**, chess **583**; formatter, --warnings-as-errors, assetbuild, diffcontrole geslaagd.
  Browsertest op dev met 3-partijen corpus: substring/colour/FEN/filter/error/open-in-room ok.

- **Afgerond, gecommit, gepusht en door de gebruiker gedeployed (bevestigd 2026-10-15):**
  twee slices bovenop de engine-serie. `45e96ea` — reviewclassificatie volgt
  nu lichess' gepubliceerde Win%-model (scalachess is MIT; de curve is gefit op echte partijen):
  cp → Win% (logistisch, clamp ±1000, mate satureert), merken bij >30/>20/>10 procentpunten
  daling voor de zetter. Positie-onafhankelijk: een 300cp-swing in een gewonnen stelling markeert
  niet meer (test bewijst het). En `Render review marks in the move list` — marks renderen inline
  naast de zet (rood ??/?, amber ?!; tooltip "Blunder · −45%"), heropbouw bij classificatie,
  wissen bij nieuwe run; nieuwe i18n room.markBlunder/Mistake/Inaccuracy EN+NL. Volledig serieel:
  web **226 geslaagd** (seed 511632), room_live 50; formatter, --warnings-as-errors, diffcontrole.
  Browsertest: Fool's mate → "2. g4 ??" in de zettenlijst, samenvatting, grafiek-prikkel rood.

- **Afgerond en gepusht — `Preserve PGN comments and annotations in room imports` (`08077d0`)**, vanaf
  schone `c045f13`. Correctie op de todo: SetUp/FEN-import bestond al sinds `1634dc32f`;
  de nieuwe webtest bevestigt ook zwart-aan-zet en het oorspronkelijke zetnummer.
  Nieuwe PgnAnalysisImporter bewaart hoofdlijnopmerkingen en NAG's in de analyse,
  stript machinecommando's uit opmerkingen en houdt canonieke partijinhoud ongewijzigd.
  Partijrecord + geannoteerde analyse worden atomair opgeslagen. Plakken/upload delen
  dezelfde importflow. Variaties blijven buiten scope en worden nog overgeslagen.
  Gericht: domain **21** en room_live **49** groen. Volledig: analysis **621** (seed 632190),
  web **225** met --warnings-as-errors (seed 552158). Assetbuild, compile --warnings-as-errors,
  formatter en diffcontrole groen.
  Eerste testcompilatie faalde door helpernaam `import` (Elixir-macro); hernoemd en opgelost.
  Geen migratie. Commit `08077d0` gepusht naar `origin/main`; deployment niet uitgevoerd/toegestaan.

- **Afgerond en gepusht — `Open personal analyses in private rooms` (`d3be41c`)**, vanaf schone `main`
  `d5ec8e9`. Gebruiker bevestigt: geen losse privé-editor; een privé-room is een gewone room.
  Bibliotheek openen maakt/hergebruikt een eigen private room en opent RoomLive. Gedeelde
  bron wordt zo nodig atomair gekopieerd, persoonlijke titel blijft behouden. Losse editor,
  route en oude private API's verwijderd. Geen nieuwe migratie; drie bestaande roommigraties
  lokaal toegepast (dev/test). Gericht domain **4** en web **32** groen; volledig analysis
  **616** (seed 668078), web **224** (seed 714072) groen. Twee bestaande waarschuwingen
  opgelost (redundante HEEx-voorwaarde/ongebruikte testvariabelen); room_live daarna **48**
  groen met --warnings-as-errors (seed 777971). Assetbuild, compile --warnings-as-errors,
  formatter en diffcontrole groen. Commit `d3be41c` gepusht naar `origin/main`. Deployment:
  **niet uitgevoerd; expliciete toestemming vereist**. Formattercontrole groen na lokale
  LF-normalisatie (CRLF veroorzaakte HEEx-formatverschillen); geen brede UI-herformattering.
  Deze status en het actuele overzicht hieronder gaan vóór oudere historische bullets.

- **Afgerond, gecommit, gepusht en gedeployed (gebruiker stond deploy toe, 2026-10-15):**
  engine-vervolgserie op `fee8abc` — `fc1e40d` (leesbare/interactieve engine-lijnen),
  `5bc9bd4` (instellingen aanpasbaar terwijl de engine draait + debounce), `018b816`
  (groene best-move-arrow op het bord), `e4a19aa` (evaluatiegrafiek), en nu **partijreview**
  (`Review game`): de hook loopt de hoofdlijn af op vaste diepte 12, de server classificeert
  wit-relatieve swings (??/?/?! bij >300/>150/>80 cp), grafiek-prikkels kleuren mee en een
  samenvatting linkt naar kritieke momenten. De sessie-evalstore is nu op **canonieke
  positie-id** gekeyed (stabiel bij edits, volgt transposities). Gericht: room_live 48;
  volledig serieel: web **234**, analysis **619**, chess **583**; formatter, --warnings-as-errors,
  assetbuild, diffcontrole geslaagd. Browsertest: review doorloopt 4 plys, grafiek vult,
  samenvatting + Review again; instellingen typbaar terwijl de engine draait.
  Productieverificatie: /health + /ready 200, wasm 200 (application/wasm); live op
  openchesslab.com: kamer CGRUL2 aangemaakt, eval +0.39, balk, arrow, review compleet.

- **Afgerond, wacht op commit/push:** `Make engine lines readable and interactive`, bovenop
  `fee8abc` (Stockfish-slice). Regels zijn nu genummerde, afzonderlijk klikbare zetten
  (wrap breekt tussen zetten); klik op zet N speelt de lijn t/m N in de analyse (één
  `Analyses.play/3` per zet, stale-fen-guard); hover toont na 180 ms een debounced mini-bord
  met de stelling ná die zet (`engine-peek`, overleeft doorlopende updates, verdwijnt bij
  mouse-away). `AnalysisView.move_context/2` levert het volgnummer; zetten dragen PGN-labels
  ("1."/"1..."). Gericht: room_live 46; volledig serieel: web **232**, analysis **619**,
  chess **583**; browsertest geverifieerd (klik speelt lijn, peek 64 velden/32 stukken).
  Vervolg in deze reeks: best-move-arrow, evalgrafiek, partijreview; daarna deploy (toegestaan).

- **Afgerond, wacht op commit/push (deploy toegestaan door gebruiker):**
  `Add client-side Stockfish analysis with an evaluation bar`, gestart op schone `bff7e93`.
  Echte engine vervangt het demopaneel: Stockfish 19 lite-single (WASM, 1,8 MB, GPLv3 + licentie
  meegeleverd) onder `priv/static/engine/`, geserveerd via nieuwe static path `engine`.
  `EngineAnalysis`-hook: worker-lifecycle, UCI-handshake, MultiPV/depth opties, throttled
  `engine-update` (~250 ms). RoomLive: `Chess.Notation.UCI` (nieuw, chess-app) zet UCI-PV's om naar
  SAN via legal-move-matching; scores worden wit-relatief genormaliseerd (UCI is side-to-move);
  stale fens en uitgeschakelde engine worden genegeerd; worker-fouten tonen een eerlijke
  fouttoestand. Instellingen: depth 1–40 + multipv 1–10, sessie-only; movetime-knop verwijderd
  (was dode UI), provider-select is nu een eerlijk statisch label. Evaluatiebalk links van het
  bord toont live scores (mate als #n). DemoData.engine_preview verwijderd. Twee bugfixes onderweg:
  HEEx boolean-attr (`to_string` voor data-engine-on) en searchKey-reset die zoekopdrachten
  herstartte bij elke push. Bijkomende fix: twee Jason-tests verhuisden van chess naar analysis
  (defimpl woonde al in analysis; chess is bewust dep-vrij). Gericht: chess 583, web room_live 44;
  volledig serieel: chess **583**, analysis **619**, web **230**; formatter, --warnings-as-errors,
  assetbuild, diffcontrole geslaagd. Browsertest: echte eval (+0,37), balk zichtbaar, settings
  bereiken de worker (MultiPV 2, depth 14), zet herstart zoekopdracht (exact 1 nieuwe `go`).

- **Afgerond, gecommit, gepusht en gedeployed (gebruiker stond deploy toe, 2026-10-15):**
  `Warn when live-sharing a library analysis into a room` (`d1210cf` op main, bovenop `949adf7`).
  Deploy geverifieerd: /health + /ready 200, beide Fly-servicechecks passing; de boot-time
  "not listening"-waarschuwing was transient (socketscan vóór de endpoint-bind).
  Gestart op schone `949adf7`.
  "Share live" opent nu eerst een bevestigingsmodal (`ui_modal: "share-confirm"`,
  `share_pending_id`): waarschuwing dat de kamer op de exacte bibliotheekanalyse werkt (elke
  bewerking landt in de bibliotheek van de eigenaar), met inline alternatieven "Deel een kopie"
  en "Deel alleen de partij" (verborgen zonder onderliggende partij) plus annuleren. Bestaande
  add-game/add-copy/share-logica verhuisd naar hergebruikte helpers; confirm-events autoriseren
  opnieuw tegen de ververste sessie. i18n EN+NL (5 nieuwe sleutels). Gericht: library_import
  **11/11**; volledig serieel: web **228 geslaagd** (seed 511632), analyse **617 geslaagd**
  (seed 398267); formatter, compile --warnings-as-errors, assetbuild en diffcontrole geslaagd.

- **Afgerond, gecommit, gepusht en door de gebruiker gedeployed (bevestigd 2026-10-15):**
  `Require stored display names for private room members` (`b5a230f` op main, bovenop `0492391`),
  browsertest: KH43QB toont echte namen, geen fallback. Deployment omvatte ook de
  member-listing/removal-slice `c092dbc` (+HANDOFF-record `0492391`); beide migraties
  (`20261014220000`, `20261015120000`) draaien via de release-migratie.
  Gebruikersbeslissing 2026-10-15: greenfield zonder gebruikers, dus
  geen legacy-compatibiliteit — de md5-fallback ("Member XXXX") uit `RoomStore` is verwijderd,
  `display_name` is `NOT NULL` (migratie `20261015120000`, dropt de twee pre-eis dev-rijen),
  `display_name` is een verplichte parameter van `create_private`/`add_member`/`consume_invite` en
  `owner_display_name` is verplicht bij `Rooms.create_room(owner: ...)`. Dev-fixture KH43QB
  handmatig gevuld vóór migratie. Gericht: domein **5/5**, web **8/8**; volledig serieel: analyse
  **617 geslaagd** (seed 398267), web **227 geslaagd** (seed 511632); formatter, compile
  --warnings-as-errors en diffcontrole geslaagd.

- **Afgerond, gecommit en gepusht:** `Add member listing and individual removal to private rooms`
  (`c092dbc` op main, bovenop `a9a08e7`), browsertest op dev geverifieerd (lijst, fallback-namen,
  join via invite, verwijdering kickt live naar de gate). Ontwerp (2026-10-15): de Invite-modal is nu de **Members**-modal van de eigenaar —
  duurzame ledenlijst (naam, eigenaar-badge, lid-sinds) + invite-link beheer in dezelfde modal.
  Namen: per lidmaatschap opgeslagen, door web gegenereerd via `Web.DisplayName` (niet-PII; legacy
  rijen krijgen een stabiele hash-fallback "Member XXXX"); private-room presence gebruikt dezelfde
  opgeslagen naam, dus de sidebar matcht de lijst. Verwijdering: alleen de eigenaar, eigen lidmaatschap
  onaantastbaar, forge/deletes van niet-leden en niet-eigenaren falen stil; `Rooms.remove_member/3`
  publiceert `membership_changed` over de room-eventgroep zodat de verbonden view van het verwijderde
  lid direct naar de gate redirectet (opgesplitst uit handmatige tests; zicht in browserflow). Migratie
  `20261014220000` (display_name kolom). Gericht: domein private_room **5/5**, web private_room **8/8**;
  volledig analyse **617 geslaagd** (seed 398267) en web **227 geslaagd** (seed 511632, serieel —
  parallelle suites corrupten de gedeelde testdb, niet herhalen); formatter, assetbuild, compile
  --warnings-as-errors en diffcontrole geslaagd.

- **Afgerond, door agent gecommit en gepusht:** `Add private rooms with owner and invite links`,
  gestart op schone `1006b71`. Besluiten gebruiker 2026-10-14: publiek blijft de default (draagbare
  kamercodes ongewijzigd, inclusief bestaande kamers); private kamers krijgen uitnodigingslinks
  (multi-use, intrekbaar/roterend; code alleen = geen toegang — de gate toont geen inhoud: geen
  presence/chat/analyses/abonnement). Migratie `20261014210000`: `rooms.owner_user_id` (NULL = publiek),
  `room_members` (uniek per kamer+user; owner wordt eerste lid), `room_invites` (alleen token-hash 32B,
  één actieve link per kamer; rotate = vorige intrekken). Domein: `Rooms.create_room(owner:)`,
  `member?/2`, `consume_invite/3` (row-lock vs. gelijktijdige revoke; ON CONFLICT idempotent),
  `create_invite/1` (rauw token eenmalig teruggegeven), `revoke_invites/1`, `invite_active?/1`;
  RoomStore volledig hash-only. Web: "Privékamer"-schakelaar op Create Room (alleen ingelogd),
  privékamer-gate in RoomLive-mount (geen subscribe/presence/chat/uploads), Invite-knop i.p.v.
  Copy code (owner-only), invite-modal (link eenmalig getoond + kopiëren + roteren/intrekken),
  `GET /rooms/:code/join/:token` (gast → gate-melding; geldig → lid + redirect; ongeldig → melding).
  Devserver-bevinding: de umbrella-code-reloader herlaadt alleen de web-app — bij domeinwijzigingen
  herstarten; oude devserver (stond sinds sep. 29 aan poort 4000) was al verwijderd en vers gestart.
  Gericht: domein private_room **4/4**, web private_room **6/6**; volledig analyse **616 geslaagd**
  (seed 398267) en web **225 geslaagd** (seed 511632); formatter, assetbuild, compile
  --warnings-as-errors en diffcontrole geslaagd. Browsergeverifieerd op devserver: UI-flow
  create→gate→invite→join→lid werkt end-to-end.

- **Afgerond, door agent gecommit en gepusht:** `Color move annotations by their meaning`,
  gestart op schone `5005b64` (gebruikersidee 2026-10-14). NAG's in de zettenlijst (room + privé-editor,
  zelfde `move_list`-component) zijn nu per glyf gekleurd naar eigen betekenis: goed/brilliant
  (1 `!`, 3 `‼`) → `text-success`, fout/blunder (2 `?`, 4 `⁇`) → `text-error`, interessant/dubieus
  (5 `⁉`, 6 `⁈`) → `text-warning` (was: alles oranje). Gebruikt de net thema-adaptieve tokens, dus
  AA-contrast in beide thema's; per-glyf spans i.p.v. één span. De NAG-paletknoppen blijven neutraal
  (besturing, geen annotatie). Web-only; geen migratie/i18n. Test: bestaande NAG-test uitgebreid met
  alle zes klassen; gericht room_live + personal_analysis **54/54**; volledig web **219 geslaagd**
  (seed 511632); formatter, assetbuild, compile --warnings-as-errors en diffcontrole geslaagd.
  Browsergeverifieerd op devserver (licht thema): 2/4 → #a84848, 3 → #387038, 5/6 → #8f6120.

- **Afgerond, door agent gecommit en gepusht:** `Make status colors theme-adaptive for light-mode
  contrast`, gestart op schone `8fb222b` (bevinding UI-pass 2026-10-14: `--error` mat 2.82:1 op wit —
  WCAG-AA-faal; `--warning`/~2.3:1 en `--success`/~2.0:1 hadden hetzelfde gebrek). `--error/--success/
  --warning` zijn nu thema-adaptief zoals `--focus`/`--highlight` (beide light-blokken in app.css):
  licht `#a84848`/`#387038`/`#8f6120`, donker ongewijzigd. CSS-only. Browsergeverifieerd op devserver:
  delete-knop 5.70:1 (was 2.82), NAG-waarschuwing 4.90:1, success-dot zichtbaar; donkere tokens
  ongewijzigd (geen regressie). Websuite **219 geslaagd** (seed 511632); formatter, assetbuild en
  diffcontrole geslaagd.

- **Afgerond, door agent gecommit en gepusht:** `Return to the room after login, link or logout`,
  gestart op schone `3f06461` (gebruikersbevinding 2026-10-14: inloggen/uitloggen in een room
  stuurde naar home; terugkeren naar de room gewenst, zoals het oude blunderfest-project via de
  OAuth-state deed). Nieuwe `Web.ReturnTo.sanitize/1`: alléén interne `/rooms/<code>`-paden
  (geen query/slash, ≤64 bytes) — een gesmede waarde kan nooit een open redirect worden
  (ergste geval de room-"niet gevonden"-melding); anders `nil`→home. De login/link-formulieren
  (header + account-modal) en logout-formulier in de roomshell dragen een verborgen
  `return_to`; de OAuth-attemptcontext bewaart het serverside (versleuteld, browsergebonden —
  callbackparameters kunnen het niet overschrijven; oude pogingen missen de key → home).
  Callback: succes én link-conflict keren terug naar de room; overige falers → home (context
  niet beschikbaar). Logout leest het veld met dezelfde sanitatie. Editor-logout blijft → home
  (auth-vereiste route). `with`→`case`-herstructurering omdat else-bindings geen clausulevars
  zien. Web-only; geen migratie/i18n. Nieuwe auth_return_to_test **6/6** (terugkeer bij
  login/link/logout; formulier alleen in room; gesmede interne/externe/lijst-waarden → home;
  callback-override onmogelijk). Volledig web **219 geslaagd** (seed 511632); formatter,
  compile --warnings-as-errors en diffcontrole geslaagd.

- **Afgerond, door agent gecommit en gepusht:** `Add header and account-menu icons with provider marks`,
  gestart op schone `8575360` (gebruikersidee 2026-10-14). Header: **Help** is nu een icon-only `?`-knop en
  **Account** een icon-only persoon-icoon (geen namen/initialen: privacy-model; aria-label+title blijven
  gelokaliseerd). Menu-items dragen iconen: bibliotheek (My Library), link (Linked accounts), logout.
  Gast-login-items dragen providermerken: het Lichess-paard (lila, AGPLv3 — compatibel met dit
  GPL-3.0-or-later project; attributie in nieuwe `apps/web/priv/NOTICE.md`, dezelfde mark als het oude
  ~/blunderfest-project) en de Google-"G" volgens Google's sign-in-brandingrichtlijnen (standaardkleuren,
  lokaliseerbare tekst). Nieuwe stroke-iconen (person/library/logout/link) + `lichess_mark`/`google_mark`
  als fill-componenten; `web.ex` importeert ze voor de layout. Web-only; geen migratie/i18n-wijzigingen.
  Gericht: auth_controls **11/11**, account_linking **9/9**; volledig web **213 geslaagd** (seed 511632);
  formatter, assetbuild, compile --warnings-as-errors en diffcontrole geslaagd. Browsergeverifieerd op
  devserver: icon-only summaries met gelokaliseerde aria-labels, menu-iconen aanwezig; login-merken
  gedekt door de tests (devserver heeft geen OAuth-config).

- **Afgerond, door agent gecommit en gepusht:** `Close modals with Escape from focused inputs`,
  commit `1536dae`. De globale `AppUI`-keyhandler behandelde Escape vóór de
  typing-guard (gebruikersbevinding 2026-10-14: modal sluit niet bij focus in een
  invoerveld — klopte: de `typing`-guard slikte ook Escape). Browsergeverifieerd:
  account-modal sluit vanuit het bevestigingsveld, import-modal vanuit de
  PGN-tekstvlakte; letter-sneltoetsen blijven geblokkeerd tijdens typen. JS-only.

- **Afgerond, wacht op commit/push:** `Split library management from importing`,
  gestart op schone `1536dae` (gebruikersidee 2026-10-14). Het "My Library"-tab van
  de importmodal bevat nu alléén importacties (Partij / Analysekopie / Live delen;
  geen editor-links, hernoemen of verwijderen meer). Onder het Account-menu is de
  beheer-modal terug: "Mijn bibliotheek" opent `library_modal` met editor-links,
  hernoemen, verwijderen en paging (`ShellPanels.open_library`; `library-`-events
  gedeeld met het tab). Beide hosts (home+room) route `open-library`/`library-*`.
  Web-only; geen migratie; geen i18n-wijzigingen nodig. Gericht: library_modal
  **8/8**, library_import/library_tracking/auth_controls **20/20**; volledig web
  **213 geslaagd** (seed 511632); formatter, assetbuild, compile
  --warnings-as-errors en diffcontrole geslaagd. Browsergeverifieerd op devserver
  (beheermodal: editor-links/hernoemen/verwijderen; importtab: alleen
  brancknoppen; Escape sluit beide).

- **Afgerond, door agent gecommit en gepusht:** `Remove the demo save-to-library from the paste
  import`, gestart op schone `1c1a66f`. Besluit gebruiker (2026-10-14): bibliotheek-entry
  uitsluitend via de ster; import is room-only, niets wordt automatisch bewaard. De nep-knop
  "Save to library" op de paste-tab is verwijderd (handler bewaarde niets, alleen een
  in-memory lijst die na slice C nergens meer zichtbaar was); ook de dode `@library_games`
  state, `remove-library-game` en vijf dode i18n-keys zijn weg. `open-demo-game` gebruikt nu
  alleen `DemoData` (zoekmodal-DEMO blijft). Web-only; geen migratie. Gericht room_live +
  library_import **53/53**; volledig web **207 geslaagd** (seed 511632); formatter,
  assetbuild, compile --warnings-as-errors en diffcontrole geslaagd.

- **Afgerond, door agent gecommit en gepusht:** `Arm the account deletion button on the
  confirmation word`, gestart op schone `5394e91` (gebruikersidee, 2026-10-14). De "Delete my
  account"-knop in het linked-accounts-modal staat op disabled tot het getypte bevestigingswoord
  klopt (`account-delete-change` host-event → `Web.AccountController.confirmation_valid?/1`,
  dezelfde servercontrole als de POST; herstelt op false bij heropenen). De verouderde
  "type the confirmation word"-melding is nu alleen nog het antwoord op buiten de browser
  gemaakte requests; de servercontrole blijft gezaghebbend (verdediging getest). Web-only.
  Gericht: account_deletion **6/6** (incl. nieuwe arming-test); volledig web **207 geslaagd**
  (seed 511632); formatter, compile --warnings-as-errors en diffcontrole geslaagd.

- **Afgerond, door agent gecommit en gepusht:** `Materialize a private copy when opening a live
  reference`, gestart op schone `0b38cca`. `UserLibrary.open_private/2` opent een bibliotheekentry
  voor privé-werk: is de analyse nog gedeeld (in een room óf door een andere gebruiker gereferenceerd),
  dan materialiseert één keer een eigen kopie, herpint de entry naar de kopie en geeft de kopie-id
  terug (idempotent; roomoriginal + andermans referenties blijven onaangetast; titel blijft staan).
  `Web.PersonalAnalysisLive` live-redirectt naar de canonieke kopie-URL (met `?p=`) en de editor werkt
  daarna op de privé-kopie; get_private/edit_private blijven de privé-scope forceren. Web+domain;
  geen migratie. Gericht: private_analysis **7/7**, web personal_analysis/library_tracking **16/16**;
  volledig analyse **612 geslaagd** (seed 398267) en web **206 geslaagd** (seed 511632); formatter,
  compile --warnings-as-errors en diffcontrole geslaagd. Daarna direct de delete-UX-slice (zie
  volgende entry).

- **Afgerond, door agent gecommit en gepusht (nieuwe werkwijze):** `Fix dark-mode contrast of the
  share and star actions`, gestart op schone `3f58fb5`. Diagnose: `--accent` (#35507e) is een
  bewuste vulkleur (altijd met witte tekst; niet thema-adaptief) — accent als tekst/rand op
  panel (~2:1 in dark mode) was mijn afwijking, geen designkeuze. Share live-knop nu het
  gevestigde primair-actiepatroon (`bg-accent text-white border-accent-strong`); ster gebruikt
  het thema-adaptieve `--highlight` (cyan in dark, donker teal in light), net als actieve
  selecties. Ook opgeruimd: drie ongebruikte `id`'s in gast-guardheads, en de twee midden in
  de eventclausules geplaatste `defp`s (clausulegroeperingswaarschuwingen) verplaatst naar het
  privé-helpergebied; `mix compile --warnings-as-errors` nu schoon. Gericht **57/57**; volledig
  web **205 geslaagd** (seed 511632); formatter, assetbuild en diffcontrole geslaagd.
  Deployment volgt gebruikersgericht.

- **Afgerond en gedeployed:** `Make following another viewer perceptible`, commit `3f58fb5` —
  door de gebruiker gepusht en gedeployed op 2026-10-14; follow-melding en stale-knopverberging
  live in productie.

- **Afgerond, wacht op commit/push:** `Make following another viewer perceptible`, gestart op
  schone `946fc21`. `follow-viewer` meldt nu altijd wat er gebeurde (`room.followedViewer`,
  naam uitsluitend serverzijde uit presence, nooit uit event-parameters) — ook als je al op
  de gevolgde positie zat, precies het geval dat "niets deed". De avatar-knop verbergt zich
  zodra de gevolgde analyse niet meer in de room staat (voorwaarde gebruikt het bestaande
  `viewing`); de stille no-op blijft alleen voor gesmede events. Eerste testdekking voor het
  volledige follow-flow (twee views, presence, notice, patch, verwijdering). Web-only,
  geen migratie. Gericht room_live **42/42**; volledig web **205 geslaagd** (seed 511632);
  formatter en diffcontrole geslaagd. Niet gedeployed.

- **Afgerond, gepusht en gedeployed:** `Open library entries into rooms from the import modal`, commit `946fc21`,
  gestart op schone `e3dd2ee`. Het "My Library"-tab van de importmodal is nu de echte en
  énige bibliotheekinterface (room-only); de account-menu-knop en het bibliotheek-modal zijn
  verwijderd. `UserLibrary.page/2` rapporteert per entry de onderliggende partij
  (codec-decode). Drie expliciete branch-acties per entry: `branch_game/2` (alleen de partij
  via `Analyses.create_from_game_record/2`; privé-analyse blijft privé), `branch_analysis/2`
  (onafhankelijke momentopname) en `authorize_share/2` (live delen: zelfde analyse, roomwerk
  verschijnt in de bibliotheek; ster vult). Toevoegen sluit de modal, ververst de room,
  selecteert de analyse en meldt het resultaat; gasten/ingetrokken sessies kunnen niet
  branchen. Demo-tab vervangen; paste-demo onaangeroerd. Geen migratie. Hernoemen/verwijderen/
  paging werken in het tab (gedeelde ShellPanels-events). Gericht: analyse library_branch/
  library_tracking/library_title **13/13**, web library_import/library_tracking/
  personal_analysis/room_live/auth_controls **65/67→na herstel groen** (auto-select-redirect
  en nul-gepadde paging-ids gecorrigeerd); volledig analyse **610 geslaagd** (seed 398267)
  en web **204 geslaagd** (seed 511632); formatter en diffcontrole geslaagd.
  Commit/push geverifieerd; op 2026-10-14 gedeployed (gebruiker).

- **Afgerond, gepusht en gedeployed:** `Track room analyses from a library star`, commit `e3dd2ee`, gestart op
  schone `0270cd6`. Vast productmodel ( zie "Afgesproken model"): room→bibliotheek is nu een
  **live referentie** via een ster op iedere analyse-entry (`UserLibrary.track_from_room/3`,
  idempotent, row-locks, géén kopie; `copy_from_room/3` en de save-a-copy-knop zijn verwijderd).
  Optimistische ster (vult direct, revert+melding bij falen), un-track verwijdert alleen de
  referentie; gasten/ingetrokken sessies zien geen ster en kunnen niet tracken. `tracked/2`
  laadt sterstatus bij iedere roomverversing. Privé-editor weigert live referenties (bewust,
  tot branchen een kopie materialiseert); editor-tests gebruiken nu een standalone privé-entry.
  i18n EN/NL; ster-icoon toegevoegd. Geen migratie. AGENTS/architecture/development-history
  dragen het herziene besluit. Gericht: analyse library_tracking **5/5**, web library_tracking/
  personal_analysis/library_modal **25/25**; volledig analyse **605 geslaagd** (seed 398267)
  en web **203 geslaagd** (seed 511632); formatter en diffcontrole geslaagd.
  Commit/push geverifieerd; op 2026-10-14 gedeployed (gebruiker).

- **Afgerond, gepusht en gedeployed:** `Allow unlinking non-final linked providers`, commit `0270cd6`,
  gestart op schone `923629d`. `Analysis.Accounts.unlink/2` verwijdert alle identiteiten
  van één provider na row-locks; de laatste resterende provider weigert met
  `:last_identity` (geen herstel, dus nooit lockout), concurrente unlinks kunnen samen
  nooit de laatste identiteit weghalen (getest met tasks). Sessies blijven geldig;
  opnieuw koppelen kan daarna. UI: Unlink-knop per gekoppelde provider in het
  linked-accounts-modal (host-event, gasten/ingetrokken sessies fail closed),
  foutmelding in-modal (`account_error`). i18n EN/NL. Geen migratie. Deploymentstatus:
  modal-slice `923629d` is door de gebruiker gedeployed; fly-checks 2/2 groen, /health
  en /ready OK; de flyctl-waarschuwing "not listening on 0.0.0.0:8080" is
  boot-timing-ruis van de proces-scan (endpoint bindt kort daarna op [::]:8080, dat is
  correct voor fly-proxy via IPv6) — geen actie nodig, niet "oplossen" naar 0.0.0.0.
  Tests: gericht user_identity **12/12** (incl. concurrency) en account_unlink **3/3**;
  volledig analyse **604 geslaagd** (seed 398267) en web **203 geslaagd** (seed 511632);
  formatter en diffcontrole geslaagd. Commit/push geverifieerd; op 2026-10-14 gedeployed (gebruiker).

- **Afgerond, wacht op commit/push:** `Open library and linked accounts as shell modals`,
  gestart op schone `01e232a`. My library en Linked accounts zijn nu shell-modalen boven
  de home- en room-LiveViews (`Web.ShellPanels` + `Web.Layouts`-templates, geopend vanuit
  het header-accountmenu); de routes `/account` en `/library` zijn verwijderd, alleen de
  privé-editor `/library/:id` resteert in de geauthenticeerde live-session. Modal-events
  blijven host-level: `Web.UserAuth` hervalideert vóór iedere handler en elke actie
  controleert de geresolveerde gebruiker; gasten/ingetrokken sessies krijgen alleen de
  login-variant. OAuth-callbacks en verwijderingsfouten verwijzen nu naar `/`. Geen migratie.
  Vastgesteld productmodel (gebruiker, 2026-10-14): **een room is een tijdelijke analysesessie**
  (solo is gewoon), **de bibliotheek is de duurzame privévoorraad**, uitnodigen moet
  "gewoon werken" omdat je al in een room zit; daarnaar converged de editor (één editor,
  twee contexten). Gericht: library_modal 10/10 en account_deletion 5/5; account_linking/
  auth_controls/personal_copy/personal_analysis-tests aangepast. Volledig web **200 geslaagd**
  (seed 511632); formatter en diffcontrole geslaagd. Niet gecommit; niet gedeployed.

- **Afgerond en gepusht:** `Add self-service account deletion`, commit `01e232a`, gestart op schone `98a2ae4`.
  `POST /account/delete` via `Web.AccountController` (CSRF + verplichte login) met getypte bevestiging
  (DELETE/VERWIJDER, case-insensitief) en een danger zone op /account (EN/NL). Hergebruikt
  `Analysis.Users.delete/1`: identities, sessies en persoonlijke bibliotheeklinks cascaderen;
  analyses en roomcontent blijven bestaan (losgemaakte persoonlijke kopieën wachten op orphancleanup).
  Een bevrijde provider-identiteit is daarna koppelbaar aan een ander account. Geen migratie.
  Aanleiding: productielogins met Lichess en Google maakten twee interne accounts; koppelen wees
  terecht een conflict af (getest gedrag). Google-productiestatus: OAuth-client aangemaakt (één
  webclient, redirect `https://openchesslab.com/auth/google/callback`), Fly-secrets gestaged met
  `--stage`, deployment door gebruiker bevestigd; productie toont beide loginknoppen (gecontroleerd
  2026-10-14). Gericht **5/5** geslaagd (account_deletion_test); volledig web **202 geslaagd**
  (seed 511632); formatter en diffcontrole geslaagd. Lokale PostgreSQL-role `openchesslab` plus
  dev/test-databases op deze machine aangemaakt (sudo door gebruiker); testmigraties uitgevoerd.
  Commit/push `01e232a` geverifieerd op origin/main; niet gedeployed.

- **Afgerond en gepusht:** `Add Google login and explicit account linking`, commit `2640d90`, gestart op schone `ff0a191`.
  Google OIDC (alleen openid), gezamenlijke OAuth-controller, expliciet koppelen via /account.
  Koppelen vereist dezelfde nog geldige sessie bij start/callback en na providerexchange;
  bestaand eigenaarschap wordt niet overgedragen of samengevoegd. Lichess-import blijft later.
  Pogingenmodule/tabel gegeneraliseerd naar OAuthAttempts/oauth_attempts;
  migratie 20261014160000 lokaal dev/test uitgevoerd (test buiten sandbox wegens Mix-lock).
  Gericht 63 geslaagd (seed 988516); uitgebreid volledig web **197 geslaagd** (seed 511632),
  analyse **602 geslaagd** (seed 398267), database **4 geslaagd** incl. release-idempotentie.
  Assetbuild, formatter en diffcontrole geslaagd. Geen testfouten; Mix-lock blokkeerde
  enkele starts vóór uitvoering, buiten sandbox uitgevoerd. Commit/push `2640d90` geverifieerd; niet gedeployed.
  Setup en handmatige acceptatie: [docs/google-auth.md](google-auth.md).
  Google-clientconfiguratie en echte providerlogin zijn nog niet uitgevoerd; productie niet gewijzigd.


- Slice afgerond en gepusht: `Add readable titles to personal library analyses`, commit `cc392f3`, start op schone `561ed67`.
  Persoonlijke titel op `user_analyses`, hernoemen in bibliotheek en tonen boven privé-editor.
  Dev/test-migratie `20261014150000` uitgevoerd. Eerste gerichte domeinrun 9/13 doordat ik tests
  vóór de door Mix-lock geblokkeerde testmigratie startte; migratie uitgevoerd, dezelfde seed `96633` daarna 13/13.
  Gericht: 23 webtests; database: 4 tests incl. release-migratie-idempotentie geslaagd.
  Volledig: analyse **602 geslaagd** (seed `398267`), web **179 geslaagd** (seed `511632`).
  Assetbuild, formatter en diffcontrole geslaagd. Commit/push geverifieerd; **niet gedeployed**.
  Deze slice bevat één nieuwe migratie; normale release-migratie voert die bij deployment uit.

- Infra-slice: `Reduce Fly app memory to 512 MB`, expliciet gevraagd door gebruiker.
  Op 2026-10-14 live uitgevoerd: `flyctl scale memory 512 -a openchesslab -g app`.
  Eén shared CPU, 512 MB; `fly.toml` legt beide geheugenvelden op 512 vast voor volgende deployments.
  Configvalidatie en diffcontrole geslaagd; Fly-checks 2/2 en publieke /health + /ready geslaagd.
  Direct na herstart circa 227 MiB beschikbaar, geen swap. Dit is geen belastingtest;
  historische Prometheus-pieken konden bij de voorafgaande inspectie niet worden opgehaald (401).
  Gebruiker bevestigde daarna deployment van `561ed67`; geen app-tests herhaald voor die infra-slice.
  Configuratie en deze overdracht reizen samen in de infra-commit; controleer HEAD/origin na pull.

- Remote: `git@github.com:openchesslab/openchesslab.git`; branch `main`.
- Laatste geverifieerde implementatiecommit: `2640d90`, gepusht op main (Google-login/accountkoppeling).
- De gebruiker bevestigde op 2026-10-14 deployment van de laatste wijzigingen (header, privé-editor en homepage).
- Afgeronde slice: `Allow private editing of personal analysis copies`, commit/push `05c3cf6`.
- Privéroute `/library/:id`: bord, varianten, opmerkingen/NAGs, revisionconflicten en toegang per event/navigatie.
- Gericht: 5 domeintests, 17 bibliotheek/editortests en daarna 10 editortests geslaagd. Eerste webrun 16/17: conflictbericht
  verdween door URL-patch; oorzaak hersteld, dezelfde seed `262747` daarna 17/17.
- Volledig: analyse **599 geslaagd**, seed `398267`; web **175 geslaagd**, seed `511632`.
- Assetbuild, formatter en diffcontrole geslaagd. Build buiten sandbox vanwege Mix hard-link lock.
- Afgeronde slice: `Simplify home controls and align independent room entry cards`, commit/push `7c24777`.
- Homepage gereed: geen stukkenkeuze/Help, Create room uitgelijnd met codeveld,
  Create/Join-blokken onafhankelijk bij foutmeldingen; roomknoppen blijven beschikbaar.
- Gericht: 15 home/auth/voorkeurtests geslaagd. Browser: EN/NL desktop en 360px mobiel,
  actieposities/hoogtes gelijk, Create-knop/caption stabiel na onbekende code, geen horizontale overflow.
- Volledige websuite **175 geslaagd**, seed `511632`; assetbuild en formatter/diffcontrole geslaagd.
- Previewserver gestopt; werkboom na beide implementatiecommits schoon en HEAD gelijk aan origin/main.
- Header `15562fc`, privé-editor `05c3cf6` en homepage `7c24777`: **deployment bevestigd door gebruiker**.
- Deze afsluitende documentatiecommit registreert de geverifieerde commit/push-status.

## Eerstvolgende productwerk

De actuele main bevat Google/Lichess-login en koppelen/ontkoppelen, accountverwijdering,
shellmodals, private rooms met uitnodigingen, bibliotheekdelen en Stockfish met grafiek/review.
De actieve slice verwijdert de losse privé-editor ten gunste van gewone private rooms.
Vervolg: kies een kleine slice uit import of echte corpuszoekresultaten; retentiebeleid
vereist nog een productkeuze. De bekende `:invalid_occurrences`-suitefout blijft backlog.

## Compact overzicht resterend werk

Dit is een overzicht, geen vastgelegde uitvoeringsvolgorde:

- **Import:** echte eigen Lichess-partijen/studies; later herkomst, retries/synchronisatie.
  PGN-varianten meenemen; keep-opties voor annotaties/metadata uitwerken. Hoofdlijnopmerkingen
  en NAG's worden in de huidige slice bewaard; SetUp/FEN-import bestond al.
- **Zoeken:** echte corpusresultaten aan de UI koppelen; later geïndexeerd zoeken op
  schaakkenmerken, structuren/plannen en gelijkenis op grote schaal.
- **Levensduur:** bewaartermijn voor gevulde rooms bepalen; bibliotheekverwijzingen veilig
  materialiseren vóór verwijderen van roomanalyses; beleid voor verweesde analyses.
- **Rechten/accounts:** verdere rollen en herstelbeleid. Private rooms, uitnodigingen,
  expliciete game-/analysekopie, live delen en providerontkoppeling bestaan al.
- **Engine:** rijkere inzichten; eventueel multithreading (COOP/COEP) of serverengine.
  Stockfish, interactieve PV, best-move-arrow, grafiek en partijreview bestaan al.
- **UX/export:** actuele UI beoordelen op resterend analysebeheer, metadata, export en tour.
- **Techniek/schaal:** bekende `:invalid_occurrences`-suitefout, grote importbenchmarks,
  monitoring/queryprestaties; importqueue/regio-uitbreiding pas bij concrete behoefte.
- **Later:** internationale SAN-notatie.

Afgesproken model:

- Een room is een tijdelijke analysesessie; solo is een gewoon gebruik.
- Binnen een room is een analyse gedeeld; een ster in de room trackt de analyse als
  **live referentie** in de bibliotheek (roomwerk wordt gereflecteerd).
- Terugdelen vanuit de bibliotheek naar een room is een expliciete keuze: alleen de partij
  kopiëren (vertrouwelijke eigen analyse blijft privé), de analyse kopiëren, of de analyse
  live delen (zelfde analyse; roomwerk verschijnt in de bibliotheek — werken over meerdere dagen).
- Privé-bewerken materialiseert een eigen kopie; geen automatische synchronisatie;
  andermans referenties blijven de originele analyse volgen.
- Zodra private rooms met eigenaars-toestemming bestaan: waarschuwing bij live delen dat
  de gedeelde analyse dezelfde is als die in de bibliotheek en dat leden die kunnen wijzigen.
- Roomverval met verwijdering van roomanalyses is gepland; bewaartermijn nog niet vastgesteld.
  Huidige cleanup verwijdert uitsluitend oude lege rooms; analyseregels overleven rooms vandaag,
  maar zodra verwijdering komt moeten gereferenceerde bibliotheekenties eerst worden gematerialiseerd.
  Laatste tab sluiten verwijdert niets.

## Belangrijke code en grenzen

- Elixir/Phoenix umbrella: apps/analysis, chess, database, features, web. PostgreSQL is gezaghebbend, lokaal zonder Docker.
- Auth: Lichess OAuth/PKCE en Google OIDC, expliciet koppelen via /account, PostgreSQL-sessies, logout en disconnectie van andere tabs met hetzelfde credential. Accountverwijdering (getypte bevestiging) is geïmplementeerd en wacht op commit/deployment; ontkoppelen volgt later.
- `Web.UserAuth` verifieert credentials bij mounts/events; private routes gebruiken de verplichte guard.
- `Analysis.UserLibrary.copy_from_room/3` maakt een kopie en bibliotheeklink in één transactie,
  met controle en locks op actuele roomlidmaatschap/bron. Web gebruikt uitsluitend de serverselectie en geverifieerde gebruiker.
- `UserLibrary.save/2` is een intern verwijzingsprimitive, geen geautoriseerde browseractie.
- `UserLibrary.rename/3` en `title/2` beheren alleen de eigen bibliotheektitel, maximaal 120 Unicode-codepunten.
  Leeg wist de titel; geen verandering van roomwerk, andere gebruikerslinks of analyserevisie.
- Privé-editor: apps/web/lib/web/live/personal_analysis_live.{ex,html.heex};
  `UserLibrary.get_private/2` en `edit_private/5` controleren/locken de privéscope.
  De editor biedt legale zetten/promotie, varianten, opmerkingen/NAGs; position setup volgt later.
- Persoonlijke kopieën krijgen een nieuw ID en zijn niet aan een room gekoppeld. Canonieke posities blijven herbruikbaar.
- Bibliotheek verwijderen verwijdert momenteel alleen de link; accountverwijdering verwijdert user,
  identities, sessies en bibliotheeklinks (analyses blijven); orphancleanup blijft apart werk.
- Shared header: apps/web/lib/web/components/layouts/app.html.heex en layouts.ex.
- Productiedomein openchesslab.com, Fly-app openchesslab. Handmatige deployment; nooit automatisch deployen.
- Productie-HMAC-sleutel bestaat en moet stabiel blijven: nooit opnieuw genereren of uitprinten.
- Sommige oude passages in AGENTS/architectuur beschrijven een historische baseline. Gebruik nieuwere secties en code.

## Andere laptop voorbereiden

1. Clone de remote of werk een schone checkout bij met `git pull --ff-only origin main`.
   Bewaar lokale wijzigingen eerst; nooit blind resetten. Ongepushte bestanden reizen niet mee via Git.
2. Controleer `git status --short`, `git branch --show-current`, `git rev-parse HEAD`, `git log -5 --oneline`.
3. Installeer een passende Elixir/OTP-toolchain volgens Dockerfile/mix.exs.
   Hier getest: Elixir 1.20.4, OTP 29 (erts 17.0.6); controleer de werkelijke versies.
4. Start native PostgreSQL en configureer lokale dev/test-databases volgens config/dev.exs en config/test.exs.
   Testhelpers voeren TRUNCATE uit: uitsluitend openchesslab_test gebruiken, nooit productie/dev.
5. `mix deps.get`; voer migraties uit vanuit apps/database voor dev en test.
   Testomgeving: PowerShell `$env:MIX_ENV = 'test'`, daarna `Remove-Item Env:MIX_ENV`;
   Bash `MIX_ENV=test mix ecto.migrate`.
   Verwijder DATABASE_URL alleen als die ten onrechte de lokale configuratie overschrijft.

Deze commando’s werken vanaf de umbrella-root in PowerShell en Bash; voer suites na elkaar uit:

```text
mix format --check-formatted
cd apps/database
mix test
cd ../analysis
mix test --seed 398267
cd ../web
mix test --seed 511632
mix assets.build
cd ../..
git diff --check
```

Voor web-only wijzigingen volstaat de relevante websuite; voer analyse niet nodeloos opnieuw uit.
Laatste volledige controle: web **200 geslaagd**, seed 511632 (modal-slice; analyse/database ongewijzigd
ten opzichte van de eerdere 602/4).
Geaccepteerde backlog: suite-afhankelijke `:invalid_occurrences`-fouten, seed 938846,
in AnalysesTest/PgnBatchImporterTest; zie development-history. Niet onderdrukken of een falende run groen noemen.

Reproductie van de Google-authenticatieslice,
dezelfde Git-commando’s op beide systemen:

```text
git add <expliciet-gecontroleerde-bestanden>
git commit -m "Add Google login and explicit account linking"
git push origin main
```

## Afrondingsstatus

Header is gepusht in `15562fc`; privé-editor in `05c3cf6`; homepage in `7c24777`.
Controleer na pull de werkelijke HEAD en werkboom; commit/push staan afzonderlijk hierboven.
Deployment van de laatste wijzigingen is op 2026-10-14 door de gebruiker bevestigd.
Geen resterende controles of implementatie voor deze twee slices.
Bibliotheektitels zijn groen en gepusht in `cc392f3`; deze nieuwe slice is niet gedeployed.
Expliciet terugdelen, gewijzigde roomretentie en privé-position setup/tools blijven later werk.

Google-login en accountkoppeling: groen en gepusht in `2640d90`; gedeployed en productielogins
geverifieerd door de gebruiker. Accountverwijdering: groen en gepusht in `01e232a`; niet gedeployed.
Modal-slice, ontkoppelen, ster en import-tab: gepusht (`923629d`, `0270cd6`, `e3dd2ee`, `946fc21`) en gedeployed.
Verificatie na deployment: modalen openen boven home/room, verwijderen met bevestigingswoord en het
daarna koppelen van de vrijgekomen Google-identiteit aan het Lichess-account (zie google-auth.md).
