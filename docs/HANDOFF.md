# OpenChessLab — overdracht voor Codex en OpenCode Go

Bijgewerkt: 2026-10-15. Dit is het compacte startpunt voor een andere laptop of agent.
Git en de actuele broncode zijn leidend. Werk dit bestand bij bij iedere slice en vóór een onderbreking:
status, resterende stappen, uitgevoerde tests, commit/push en deployment afzonderlijk.
Geen geheimen, tokens of lokale databases opnemen.

## Startprompt

> Ga verder met OpenChessLab. Lees eerst docs/HANDOFF.md en AGENTS.md, daarna de relevante delen van docs/architecture.md en docs/development-history.md. Inspecteer git status, branch, HEAD en recente commits. Rond eventueel openstaand werk hieronder eerst af. Werk in kleine slices met tests. Commit en push zijn toegestaan na geslaagde controles (de agent mag sinds 2026-10-14 zelf committen en pushen, met vermelding in dit bestand); deployment vereist altijd expliciete toestemming. Houd docs/HANDOFF.md bijgewerkt. Communiceer bondig in het Nederlands en bespaar context door gericht te lezen. Gebruik geen subagents tenzij gevraagd.

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

- **Afgerond, gecommit en gepusht; deploy volgt door gebruiker:** `Persist engine evaluations per
  canonical position`, bovenop `abf39ad`. Nieuwe tabel `position_evals` (migratie
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
