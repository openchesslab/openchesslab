# OpenChessLab — overdracht voor OpenCode Go

Bijgewerkt: 2026-10-14. Dit is het compacte startpunt voor een andere laptop of agent.
Git en de actuele broncode zijn leidend. Werk dit bestand bij bij iedere slice en vóór een onderbreking:
status, resterende stappen, uitgevoerde tests, commit/push en deployment afzonderlijk.
Geen geheimen, tokens of lokale databases opnemen.

## Startprompt

> Ga verder met OpenChessLab. Lees eerst docs/HANDOFF.md en AGENTS.md, daarna de relevante delen van docs/architecture.md en docs/development-history.md. Inspecteer git status, branch, HEAD en recente commits. Rond eventueel openstaand werk hieronder eerst af. Werk in kleine slices met tests. Commit en push zijn toegestaan na geslaagde controles; deployment vereist altijd expliciete toestemming. Houd docs/HANDOFF.md bijgewerkt. Communiceer bondig in het Nederlands en bespaar context door gericht te lezen. Gebruik geen subagents tenzij gevraagd.

## Modelkeuze

Mijn praktische startadvies: **Kimi K2.7 Code**, indien zichtbaar onder OpenCode Go.
Dit is een keuze voor deze codegerichte workflow, geen bewezen winnaar op deze Elixir-repository:
we hebben hier geen vergelijkende modelbenchmark uitgevoerd.
Gebruik één model per kleine slice; beoordeel het op correcte tests en beperkte, begrijpelijke diffs.

Verbind in OpenCode via `/connect` → OpenCode Go en kies via `/models`.
De officiële [Go-documentatie](https://docs.opencode.ai/docs/go/) noemt Kimi K2.7 Code
(gecontroleerd 2026-10-14); beschikbaarheid kan veranderen. Kies het exacte model uit de lijst,
verzin geen provider/model-ID. Als het ontbreekt, is GLM-5.3 een alternatief uit dezelfde gepubliceerde lijst.
Bewaar API-sleutels via OpenCode, nooit in de repository.

## Repository en huidige status

- Remote: `git@github.com:openchesslab/openchesslab.git`; branch `main`.
- Laatste geverifieerde gepushte commit vóór deze slice: `7ea45e19d0ee660ce06bbc4486ab573f8537310e`.
- De gebruiker heeft `7ea45e1` gedeployed.
- Huidige slice: `Group header controls into theme, help and account menus`.
- Implementatie gereed: één themaknop (systeem → licht → donker), Help met sneltoetsen/tour,
  Account met Lichess-login of bibliotheek/logout. Bestaande voorkeurcookies en CSRF-formulieren blijven gebruikt.
- Menu’s sluiten via Escape/buitenklik; de stukkenkeuze op mobiel is binnen het scherm uitgelijnd.
- Validatie: 11 gerichte auth/voorkeurtests; volledige websuite **165 geslaagd**, seed `511632`;
  formatter en diffcontrole geslaagd. Browsercontrole desktop en 360px mobiel, Help/Account en themawisseling geslaagd.
- Assetbuild geslaagd; tijdelijke lokale previewserver gestopt.
- Deze headerslice is **niet gedeployed**.

## Eerstvolgende productwerk

Na afronding van de header: persoonlijke kopieën privé openen en bewerken.
Nu bestaat alleen bewaren vanuit een room plus een afgeschermde bibliotheeklijst/verwijderen.
Introduceer géén impliciete roomtoegang om een persoonlijke kopie te openen.

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
Laatste volledige analysecontrole: **594 geslaagd**, seed 398267, bij `7ea45e1`.
Geaccepteerde backlog: suite-afhankelijke `:invalid_occurrences`-fouten, seed 938846,
in AnalysesTest/PgnBatchImporterTest; zie development-history. Niet onderdrukken of een falende run groen noemen.

Na inspectie van de diff en groene controles, dezelfde Git-commando’s op beide systemen:

```text
git add <expliciet-gecontroleerde-bestanden>
git commit -m "Group header controls into theme, help and account menus"
git push origin main
```

## Afrondingsstatus

Header, tests, assetbuild en documentatie zijn afgerond. Deze overdracht wordt samen met de header
gecommit en naar main gepusht met het hierboven genoemde commitonderwerp.
Controleer op de andere laptop na pull de werkelijke HEAD en schone werkboom; de commit die
dit bestand bevat is het overdrachtspunt (geen circulair hardgecodeerde eigen SHA).
Een eerdere goedkeuringslimiet is opgeheven en de build is daarna succesvol uitgevoerd.
Er is geen deployment uitgevoerd. Volgende stap: privé openen/bewerken van persoonlijke kopieën,
tenzij de gebruiker eerst wijzigingen aan de header vraagt.
