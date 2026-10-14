# OpenChessLab — overdracht voor Codex en OpenCode Go

Bijgewerkt: 2026-10-14. Dit is het compacte startpunt voor een andere laptop of agent.
Git en de actuele broncode zijn leidend. Werk dit bestand bij bij iedere slice en vóór een onderbreking:
status, resterende stappen, uitgevoerde tests, commit/push en deployment afzonderlijk.
Geen geheimen, tokens of lokale databases opnemen.

## Startprompt

> Ga verder met OpenChessLab. Lees eerst docs/HANDOFF.md en AGENTS.md, daarna de relevante delen van docs/architecture.md en docs/development-history.md. Inspecteer git status, branch, HEAD en recente commits. Rond eventueel openstaand werk hieronder eerst af. Werk in kleine slices met tests. Commit en push zijn toegestaan na geslaagde controles; deployment vereist altijd expliciete toestemming. Houd docs/HANDOFF.md bijgewerkt. Communiceer bondig in het Nederlands en bespaar context door gericht te lezen. Gebruik geen subagents tenzij gevraagd.

## Modelkeuze

**Codex:** start met GPT-6.1 Sol, reasoning Medium, voor privé openen/bewerken en toegangscontroles.
Voor routinematige UI/documentatie is Medium een passend startpunt. Adviseer GPT-6 Astra
alleen bij lastige architectuur/concurrency of wanneer Sol aantoonbaar vastloopt; Luna kan voor kleine,
duidelijk begrensde tekstwijzigingen. Dit zijn taakgerichte aanbevelingen, geen repo-benchmark.
Bron: [OpenAI modelkeuze](https://developers.openai.com/api/docs/guides/model-selection),
gecontroleerd 2026-10-14.

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

- Remote: `git@github.com:openchesslab/openchesslab.git`; branch `main`.
- Laatste geverifieerde implementatiecommit: `15562fc`, gepusht op main.
- De gebruiker heeft `7ea45e1` gedeployed.
- Huidige slice: `Allow private editing of personal analysis copies` (werkboom, nog niet gecommit).
- Privéroute `/library/:id`: bord, varianten, opmerkingen/NAGs, revisionconflicten en toegang per event/navigatie.
- Gericht: 5 domeintests, 17 bibliotheek/editortests en daarna 10 editortests geslaagd. Eerste webrun 16/17: conflictbericht
  verdween door URL-patch; oorzaak hersteld, dezelfde seed `262747` daarna 17/17.
- Volledig: analyse **599 geslaagd**, seed `398267`; web **175 geslaagd**, seed `511632`.
- Assetbuild, formatter en diffcontrole geslaagd. Build buiten sandbox vanwege Mix hard-link lock.
- Commit/push volgen na deze controles; de commit met deze editor is het overdrachtspunt.
- Daarna aparte homepage-slice: geen stukkenkeuze/Help; Create room uitlijnen met codeveld,
  Create/Join-blokken onafhankelijk laten reageren op foutmeldingen.
- Implementatie gereed: één themaknop (systeem → licht → donker), Help met sneltoetsen/tour,
  Account met Lichess-login of bibliotheek/logout. Bestaande voorkeurcookies en CSRF-formulieren blijven gebruikt.
- Menu’s sluiten via Escape/buitenklik; de stukkenkeuze op mobiel is binnen het scherm uitgelijnd.
- Validatie: 11 gerichte auth/voorkeurtests; volledige websuite **165 geslaagd**, seed `511632`;
  formatter en diffcontrole geslaagd. Browsercontrole desktop en 360px mobiel, Help/Account en themawisseling geslaagd.
- Assetbuild geslaagd; tijdelijke lokale previewserver gestopt.
- Deze headerslice is **niet gedeployed**.

## Eerstvolgende productwerk

De header is afgerond. Persoonlijke kopieën privé openen/bewerken is nu in uitvoering.
De privé-editor vereist een eigen bibliotheeklink zonder roomlidmaatschap of andere gebruikerslink.
Geen room wordt aangemaakt of gekoppeld. Controleer de actuele werkboom en tests voor voortzetting.

Afgesproken model:

- Binnen een room is een analyse gedeeld.
- Persoonlijk bewaren maakt een zelfstandige kopie met alle varianten/opmerkingen.
- Toekomstig expliciet delen terug naar een room maakt opnieuw een kopie; geen automatische synchronisatie.
- Roomverval met verwijdering van roomanalyses is gepland; bewaartermijn nog niet vastgesteld.
  Huidige cleanup verwijdert uitsluitend oude lege rooms. Laatste tab sluiten verwijdert niets.

## Belangrijke code en grenzen

- Elixir/Phoenix umbrella: apps/analysis, chess, database, features, web. PostgreSQL is gezaghebbend, lokaal zonder Docker.
- Auth werkt: Lichess OAuth/PKCE, PostgreSQL-sessies, logout en disconnectie van andere tabs met hetzelfde credential.
- `Web.UserAuth` verifieert credentials bij mounts/events; private routes gebruiken de verplichte guard.
- `Analysis.UserLibrary.copy_from_room/3` maakt een kopie en bibliotheeklink in één transactie,
  met controle en locks op actuele roomlidmaatschap/bron. Web gebruikt uitsluitend de serverselectie en geverifieerde gebruiker.
- `UserLibrary.save/2` is een intern verwijzingsprimitive, geen geautoriseerde browseractie.
- Persoonlijke kopieën krijgen een nieuw ID en zijn niet aan een room gekoppeld. Canonieke posities blijven herbruikbaar.
- Bibliotheek verwijderen verwijdert momenteel alleen de link; orphancleanup en eigenaarschap bij accountverwijdering zijn nog apart werk.
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
cd apps/analysis
mix test --seed 398267
cd ../web
mix test --seed 511632
mix assets.build
cd ../..
git diff --check
```

Voor web-only wijzigingen volstaat de relevante websuite; voer analyse niet nodeloos opnieuw uit.
Laatste volledige analysecontrole: **599 geslaagd**, seed 398267, voor de privé-editor.
Geaccepteerde backlog: suite-afhankelijke `:invalid_occurrences`-fouten, seed 938846,
in AnalysesTest/PgnBatchImporterTest; zie development-history. Niet onderdrukken of een falende run groen noemen.

Na inspectie van de diff en groene controles, dezelfde Git-commando’s op beide systemen:

```text
git add <expliciet-gecontroleerde-bestanden>
git commit -m "Allow private editing of personal analysis copies"
git push origin main
```

## Afrondingsstatus

Header is gepusht in `15562fc`; privé-editor, tests en documentatie zijn nu groen.
Controleer na pull de werkelijke HEAD en werkboom; commit/push staan afzonderlijk hierboven.
Geen deployment uitgevoerd; ook deployment van de header is niet bevestigd.
Volgende slice: homepage vereenvoudigen en Create/Join-layout onafhankelijk uitlijnen.
Expliciet terugdelen, gewijzigde roomretentie en privé-position setup/tools blijven later werk.
