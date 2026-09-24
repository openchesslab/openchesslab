# Codebase review — Openchesslab

Datum: 24 september 2026
Basis: `e93ea6a` (2026-09-23), branch `main`, 159 commits.

Managed omgeving: Elixir 1.20.4 / OTP 29. Alle 956 tests slagen
(chess 418, position_db 246, analysis 211, web 81). Compilatie zonder waarschuwingen.

---

## 1. Overzicht

Openchesslab is een Elixir-umbrella met vier apps, in lagen van zuiver naar
concreet:

| App | Rol |
| --- | --- |
| `chess` | Purer schaakdomein: bord, bitboard, zetten, positie, codec, hashes, SAN |
| `position_db` | Query-engine en opslag (`PositionDB`) over posities: in-memory + een nieuw disk-formaat |
| `analysis` | Game tree, transities, rooms (Horde), position store als GenServer |
| `web` | Phoenix 1.8 / LiveView-frontend met lokalisatie (`localize`) |

De architectuur is helder: `chess` is volledig dependency-vrij en testbaar;
`position_db` hangt alleen van `chess` af; `analysis` en `web` tapen daarop in.
Recent werk (september 2026) focust volledig op duurzame disk-storage voor
`position_db` (manifests, record codecs, exact-index buckets).

---

## 2. Bevindingen per prioriteit

### 2.1 Hoog — Correctheidsfout in damerokade (queenside castling)

`apps/chess/lib/chess/position.ex:724-729`

`castling_cross_square/1` geeft per kleur altijd het **f-veld** terug (f1/f8),
maar dat is alleen juist voor koningsrokerad. Bij damerokade passeert de koning
**d1/d8**, niet f1/f8. `castle/6` (`position.ex:668`) bewaakt dit veld:

```
false <- attacked?(position, opponent, castling_cross_square(color)),
false <- attacked?(position, opponent, king_to)
```

Gevolgen (geverifieerd met een uitvoerbaar check-script):

- Damerokade wordt **ten onrechte toegestaan** als **d1** (wit) zich in een
  aanval bevindt terwijl f1 vrij is — de koning kruist dan een bestreken veld.
- Damerokade wordt **ten onrechte geblokkeerd** als alleen **f1/f8** bestreken
  wordt terwijl d1/d8 vrij is.

De bug sijpelt door in zowel `apply_move/2` als `legal_moves/1`
(`position.ex:210-215` filtert rokerad via `apply_move`), dus ook in SAN en in
alles dat op legitieme zetten draait.

**Testgat**: de tests "cannot castle through an attacked square"
(`position_move_test.exs:1355`, `position_test.exs:690`) gebruiken alleen
`:white_kingside`-rechten; er is geen queenside-door-aanval-test.

**Fix-suggestie**: `castle/6` ontvangt al het `right`-atoom; leid het
kruispunt-veld af uit `right` (+ richting), niet uit alleen de kleur
(bijv. `:white_queenside` → d1, `:white_kingside` → f1, zwart analoog). Voeg
tests toe voor zowel d1/d8-in-aanval (mag niet rokerad) als f1/f8-in-aanval
(mag wél rokerad).

### 2.2 Gemiddeld — Disk-storage is nog niet geïntegreerd

- `PositionDB.Storage.Disk` (`apps/position_db/lib/position_db/storage/disk.ex`)
  implementeert de `PositionDB.Storage`-behaviour nog niet en is alleen-lezen:
  er is geen `append`/`put` — alleen `get`, `find`, `cardinality`. Het moduledoc
  zegt dit ook expliciet.
- De draaiende app gebruikt dit alles niet: `Analysis.PositionStore`
  (`apps/analysis/lib/analysis/position_store.ex`) draait een in-memory
  `PositionDB` (opslag `Storage.Memory`). De recente disk-commits worden dus
  alleen door tests uitgeoefend.
- `Analysis.GameStore.Dets` (duurzaam) wordt nergens gestart; op runtime draait
  `Analysis.GameStore.Memory` (`analysis/lib/analysis/application.ex:12`).

Dit is waarschijnlijk bewuste WIP, maar de staat is verwarrend in een repo
waar verder niets WIP is. Vermeld in README of een issue dat disk-storage
experimenteel/alleen-getest is, of werk de integratie af.

### 2.3 Gemiddeld — Drie bord-representaties, prestatie- en consistentiekost

`Chess.Position.board` gebruikt `Chess.Board` (64-tuple). Elke
legale-zet-berekening en aanval-check converteert de tuple opnieuw naar een
`Chess.Bitboard` via `Bitboard.from_position/1` (`position.ex:171`,
`position.ex:165`, etc.) — per oproep, per zet. Daarnaast bestaat
`Chess.MapBoard` (map-based), dat nergens in `lib/` gebruikt wordt, alleen in
zijn eigen test.

Hierdoor:
- Frequente, herbruikbare O(P)-conversie in de heetste code-paden.
- Drie publieke API-oppervlakken om één concept te representeren.

Aanbeveling: kies één interne representatie (de bitboard-variant is het
snelst) en gebruik die als canoniek; of wrap `from_position` in een cache
(`:persistent_term`/gekraakte struct). `MapBoard` kan weg of als interne
implementatie dienen.

### 2.4 Schoonheid / duplicatie

- **Popcount** drie keer geïmplementeerd: `Chess.Bitboard` (`popcount`),
  `Chess.PositionProperties` en in de benchmarks. Eén helper volstaat.
- `PositionKey.equivalent/2` (`position_key.ex:28-38`) en
  `Chess.PositionCanonicalizer` (`position_canonicalizer.ex:6-12`) doen
  functioneel hetzelfde (min(normaal, color-swap)); de canonicalizer is
  daarmee redundant.
- `Analysis.TransitionNotation` (SAN + patch) vs. `Web.ChessNotation`
  (lokalisatie) — de lokalisatie via `String.replace_prefix` is fragiel:
  een notatie zoals `Qd1h5` of promoties leunt op prefix-matching in plaats
  van structurele parsing.

### 2.5 Laag — Web; robuustheid en UX

- `RoomLive.assign_current_occurrence` doet een harde match
  `{:ok, position} = PositionStore.get(position_id)`
  (`apps/web/lib/web/live/room_live.ex`). Ontbreekt de positie (datagat na
  duurzame storage/WIP), crasht de LiveView. Gebruik een `case` met
  herstelpad.
- Promotie is niet bereikbaar vanuit de UI: `play_move` bouwt één `Move` zonder
  `promotion`, terwijl `legal_moves` promotievarianten genereert — een bevorder
  zet is dus zichtbaar als legaal maar niet speelbaar.
- `Games.edit` staat toe een kind-positie te paren identiek aan de ouder-
  positie (zelfde `position_id`), een no-op-bewerking in de boom.

### 2.6 Project & proces

- **Geen CI**: geen `.github/` (of andere pipeline); alles draait lokaal.
- Geen `credo`/`dialyzer`-configuratie.
- Geen property-based tests (`StreamData`); alleen voorbeeld-gebaseerde tests.
- Root `README.md` en alle vier app-README's zijn boilerplate
  (“**TODO: Add description**”), net als `Chess.hello/0` en het root
  `mix.exs`-commentaar.

---

## 3. Sterke punten

- **Lagen en contracts**: gedragscollecties (`PositionDB.Storage`,
  `Storage.ExactIndex`, `Storage.ExactKeyHash`, `Storage.RecordCodec`,
  `Analysis.GameStore`) maken de disk-work sequentiële, testbare stappen.
- **Disk-formaat is degelijk ontworpen**: manifests met magic bytes + versie,
  `format_id`s, vaste `record_size`s, foutafhandeling (`:invalid_segment_size`,
  `:partial_record`), en een 67-byte `PositionCodec`. Beperkte, controleerbare
  ontkoppeling via contract-modules (`Analysis.PositionExactKeyHash`,
  `Analysis.PositionRecordCodec`).
- **Correcte kerndetails**: `position.ex` valideert materiaal-plausibiliteit,
  rokaderechten bij kick-off/vastleging, en update de en-passant-mechanica
  correct; `legal_moves` vermijdt duplicaten (geen dubbele en-passant/rokade).
- **Concurrency-model**: `games.ex` gebruikt revisies + optimistische
  concurrency; `:pg`-events voor UI-refresh; Horde voor idempotente rooms.
- **Tests**: 956 groen, breed over drie lagen, inclusief ‘negative’ gevallen en
  (in `position_db`) tmp-dir-geïsoleerde disk-tests. Conventies zijn consistent.
- Ongelabelde, consistente `@spec`s over de hele codebase.

---

## 4. Samenvatting

Een erg schone, goed doorwaadbare codebase met doordachte contracts en sterke
testdekking. De schaakkernel (laag `chess`) is één echte correctheidsfout —
`castling_cross_square/1` voor damerokade (§2.1) — verwijderd van solide,
zonder de overige structurele issues te laten bestaan.

Aanbevolen actie-route:

1. Fix damerokade-cross-square + add queenside-aanval-tests.
2. Maak `Storage.Disk`-status expliciet (README/issue) of werk de integratie
   naar `Analysis.PositionStore` af, inclusief `put`/`append`.
3. Eén canonieke bord-representatie of caching van `Bitboard.from_position/1`.
4. Maak `assign_current_occurrence` faalveilig; exposeer promoties in de UI.
5. Reken duplicatie (popcount, canonicalizer) en boilerplate op.
6. Voeg CI + credo/dialyzer toe; vervang README-placeholders.