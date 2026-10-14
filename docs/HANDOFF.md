# OpenChessLab — overdracht voor Codex en OpenCode Go

Bijgewerkt: 2026-10-14. Dit is het compacte startpunt voor een andere laptop of agent.
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

Header, privé-editor, homepage, bibliotheektitels en Google-login zijn afgerond; Google-login
is gedeployed en geverifieerd. Accountverwijdering is gepusht in `01e232a` en wacht op deployment;
de modal-slice hierboven bouwt daarop voort. Daarna verwijdert de gebruiker het dubbele
Google-account in productie en koppelt Google aan het Lichess-account. Vervolg daarna:
bibliotheek-entries delen naar rooms (docentmodel) en de privé-editor laten convergeren.
Geen room wordt aangemaakt of gekoppeld. Controleer de actuele werkboom en tests voor voortzetting.
Vervolg: privé-position setup/tools. Expliciet terugdelen
en gewijzigde roomretentie komen later; introduceer geen automatische synchronisatie.

## Compact overzicht resterend werk

Dit is een overzicht, geen vastgelegde uitvoeringsvolgorde:

- **Persoonlijke werkruimte:** titels/labels zijn geïmplementeerd; position setup/tools volgen in
  de room-editor (één editor, twee contexten; de privé-editor convergeert daarin).
- **Delen en levensduur:** expliciet kopiëren terug naar rooms; bewaartermijn en verwijderen van gevulde rooms;
  beleid voor verweesde analyses en bibliotheekverwijdering; accountverwijdering is geïmplementeerd,
  orphancleanup van losgemaakte persoonlijke kopieën volgt later.
- **Lichess-data:** eigen partijen/studies importeren; later synchronisatie, herkomst, retries en minimale toestemmingen.
- **Echte engine en partijreview:** providerkeuze (browser/server), evaluaties/varianten; daarna partijanalyse,
  fouten/momenten en evaluatiegrafieken. Huidige enginepaneel is nog geen echte engine.
- **Zoeken:** echte corpuszoekresultaten aan UI koppelen; later geïndexeerd zoeken op schaakkenmerken,
  structuren/plannen en gelijkenis op grote schaal.
- **Samenwerkingsrechten/accounts:** rollen, delen/eigenaarschap; private rooms met expliciete
  toestemming van de eigenaar (oplossing voor room-privacy; daarna convergeert de privé-editor weg).
  Google/Lichess koppelen is geïmplementeerd, ontkoppelen en herstelbeleid volgen later.
- **Bibliotheek als voorraad (docentmodel):** vanuit een room een eigen bibliotheekanalyse toevoegen
  aan die room (kopie; eventueel alleen de partij); vanuit home een nieuwe room starten vanuit een entry.
  Daarna is de privé-editor volledig vervangen en wordt die verwijderd.
- **Room-UX, opgelost in `Make following another viewer perceptible` (2026-10-14):** de
  aanwezigheidsavatars leken niets te doen; `follow-viewer` werkt en meldt nu zichtbaar wat
  er gebeurde, en de knop verbergt zich bij een verdwenen analyse. Opmerking blijft relevant:
  Tailwind v4-preflight geeft álle knoppen `cursor:pointer` (native browser-default is `default`).- **UX/export:** resterende punten uit de historische UI-catalogus eerst aan actuele code toetsen;
  onder meer analysebeheer, partijmetadata, rijkere export, grafieken en een tour met gerichte highlights.
- **Techniek/schaal:** bekende `:invalid_occurrences`-suitefout; grote importbenchmarks, monitoring,
  queryprestaties en pas bij concrete behoefte een importqueue/verdere regio-uitbreiding.
- **Lager/later:** overige UI-polish en eventuele internationale SAN-notatie.

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
