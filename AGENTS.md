# OpenChessLab — instructions for Codex

> Baseline when this handoff was prepared: `main` at `51192f5acceff601fe8b1bef225146eed72d0831` (2026-10-13). **The checked-out Git repository, not this document, is the source of truth.** These instructions apply to work in this repository. Read [`docs/architecture.md`](docs/architecture.md) for verified architecture and [`docs/development-history.md`](docs/development-history.md) for rationale, measurements, and backlog.

## Mission and non-negotiable decisions

- OpenChessLab is a **greenfield** collaborative chess analysis product, with **no established users or compatibility obligations**. Prefer direct, well-tested design improvements to adapters, dual implementations, compatibility shims, or migration scaffolding for hypothetical legacy clients.
- **PostgreSQL is authoritative** for positions, canonical games, occurrences, concrete game records, analyses, rooms, and identity/library records. Use PostgreSQL's transactions, constraints, indexes, query plans, and concurrency primitives rather than building a custom DBMS. PostgreSQL is installed locally, **not in Docker**.
- Analyses and canonical played games are different concepts: analyses are mutable, branching, may contain illegal/what-if positions; canonical games are legal ordered move content with deduplication, occurrences, and concrete metadata records.
- A room is a collaboration context. Room/analysis membership is durable, room worker/chat/presence are transient. **Library model (2026-10-14, refined same day):** a library star tracks the room's own analysis as a **live reference** — room work is reflected in the library while the analysis exists. Bringing a library entry into a room is an explicit choice: copy the underlying game only, copy the analysis, or live-share the analysis itself; opening a library entry uses the ordinary private-room editor, reusing an owned room or materializing a separate copy when shared. There is no standalone private editor. No automatic synchronization; others' references keep tracking the original. **Private rooms (implemented 2026-10-14):** public rooms stay bearer-code links (knowing the code is entry); private rooms have an owner, membership rows and revocable rotating invite links — the code alone never grants entry and the gate leaks nothing. **Retention (implemented 2026-10-16):** populated rooms are pruned after **3 days without activity** (a visit, move, comment or chat message resets the clock via `rooms.last_active_at`); old empty rooms are still pruned at 30 days by creation date. Before a room's analyses are deleted, library references to them are materialized into independent copies — a pruned room never takes saved work. Closing the last tab must not delete work.
- Privacy-first authentication: **one internal User has zero or more linked Accounts**. No email, real name, password, provider username, or raw provider subject is stored in the identity schema. Provider subjects are represented by server-keyed HMAC-SHA256 values. **Lichess OAuth2/PKCE and Google OIDC login/linking are implemented; provider data grants/import remain planned.** Never equate a passed user ID or an unverified provider subject with authentication. See architecture for the important limits of “no PII.”
- Keep English as the default UI language; Dutch translation exists. Internationalized SAN is a future consideration, not a license to change chess notation semantics.
- Aim for ≥100M positions and ≥10M games. Prove hot-path improvements with representative benchmarks and `EXPLAIN (ANALYZE, BUFFERS)` where SQL matters; protect correctness first.

## Mandatory development loop

Keep `docs/HANDOFF.md` current at each completed slice and before interruptions. Record pending work,
actual test outcomes, commit/push status and deployment separately so the user can switch laptops
or continue with OpenCode Go at any time. Keep it concise and free of secrets.

At each new slice, briefly recommend a Codex model and reasoning effort. Explicitly suggest
switching when task complexity or observed failures justify it; do not claim to change the user's
model yourself. Verify OpenCode Go recommendations against its current official model list.

1. **Inspect first.** Before proposing a change, inspect `git status --short`, `git branch --show-current`, `git rev-parse HEAD`, relevant complete source files, migrations, tests, and recent commits. If access is through GitHub, check the exact `main` SHA. Never derive APIs, file locations, behavior, or identifiers from memory alone. If the worktree is dirty, determine why before modifying anything; preserve existing changes.
2. **Put the proposed English Git commit message at the very top** of every implementation response/step. One small, releasable vertical slice per commit. State scope and expected behavior, then supply **tests and implementation together**.
3. **Provide full, copy-pasteable files** (or a verified, executable PowerShell script and, where appropriate, a POSIX shell equivalent), not hand-wavy instructions. Valid unified patches are acceptable only if properly generated, anchored, and tested; avoid brittle clipboard diffs. If generating an edit script, verify its exact expected SHA/anchors and ensure partial failures cannot silently overwrite or corrupt files. PowerShell here-string terminators and CRLF/LF handling deserve special care.
4. **Run or request targeted tests, then relevant app/full tests**, formatting, and `git diff --check`. Fix failures and Dialyzer/compiler warnings at their cause. Do not declare tests green without executing them or receiving the user's green result. Do not silently rerun a failing test and call a nondeterministic failure acceptable.
5. Compare measured baseline and candidate **under equivalent fixtures/conditions** before accepting an optimization. Keep benchmark-only experiments out of production until justified. Revert regressions rather than defending an attractive but slower idea.
6. After a green step, immediately repeat the exact **English commit message** and provide cross-platform commit/test instructions. The user normally commits and pushes and reports the short SHA; verify the new repository state before the next step.
7. **Manual deployment is the established workflow.** Do not re-enable GitHub/Fly auto-deploy or deploy production without explicit user direction. The user verifies production afterward.

## Local development: Windows PowerShell and Arch Linux

The repository is an Elixir/Phoenix umbrella project (`apps/analysis`, `apps/chess`, `apps/database`, `apps/features`, `apps/web`). Follow `mix.exs`, `mix.lock`, `.tool-versions` if present, and the current Dockerfile rather than freezing the version numbers in this document. At handoff the Dockerfile specified Elixir 1.20.4 and OTP 29.0.6, while a previously reported Windows workstation used OTP 29.1.1; check actual toolchain compatibility.

From the **umbrella root**, with a running, locally installed PostgreSQL server and databases `openchesslab_dev` / `openchesslab_test` configured per `config/dev.exs` and `config/test.exs`:

```powershell
# PowerShell (Windows)
Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue # only if it incorrectly overrides local DB
mix deps.get
mix format
Push-Location apps/database
mix ecto.migrate
$env:MIX_ENV = 'test'; mix ecto.migrate; Remove-Item Env:MIX_ENV
Pop-Location
Push-Location apps/analysis
mix test test/analysis/user_identity_test.exs  # example targeted test
mix test
Pop-Location
Push-Location apps/web
mix test
Pop-Location
git diff --check
```

```bash
# Bash / Zsh (Arch Linux)
unset DATABASE_URL # only if an unwanted override is set
mix deps.get
mix format
(cd apps/database && mix ecto.migrate && MIX_ENV=test mix ecto.migrate)
(cd apps/analysis && mix test test/analysis/user_identity_test.exs && mix test)
(cd apps/web && mix test)
git diff --check
```

- **Format from umbrella root** with Quokka (`mix format`); Quokka is preferred over Styler. Follow repo formatter config, not an arbitrary 80-column limit.
- Never run destructive tests or benchmarks against development/production data. Several `test_helper.exs` files **TRUNCATE tables at startup**; `config/test.exs` insists the database path is `/openchesslab_test`. Benchmark programs often delete fixture data; use a disposable `openchesslab_bench` database and inspect the script first.
- If Windows reports the test database as `openchesslab_bench`, clear an inherited `DATABASE_URL` rather than weakening the test guard. PowerShell uses `$env:VARIABLE`; Bash uses `export VARIABLE=value` and `unset VARIABLE`.
- Prefer simple portable file paths/commands. Windows workspace was `C:\git\github\openchesslab`, but never assume that path exists on Arch. Do not rely on `Get-Clipboard | git apply` for hand-crafted patches.
- Tests for PGN importer, chess rules, concurrency, LiveView, and database contracts should travel with corresponding code changes. Run the umbrella app suites serially if they share the test PostgreSQL database; they currently perform destructive suite-level resets.

## Architecture, security and UX guardrails

- Authoritative code paths are documented in [`docs/architecture.md`](docs/architecture.md). Check the current source for function signatures, return types, transaction ownership, and query semantics before changing them.
- Preserve atomicity for canonical-game creation, occurrence insertion, replay and multi-game batches. Fingerprints narrow candidates; **complete content equality** determines canonical identity. Concurrent writes and deduplication need tests.
- Keep keyset paging bounded and cursor contracts stable unless deliberately redesigning them. Search runs in PostgreSQL: do not reintroduce N+1 nested paging or reconstruct a custom posting-list engine.
- Preserve the separation between current `Analysis.PositionQuery` SQL predicates and the newer `Features` catalogue. Comparing extracted feature vectors does **not** automatically mean a database-side plan-search index exists.
- Keep LiveView interaction responsive, including cross-region latency; optimistic board interaction is part of the UI history. Shared analysis URLs use `?a=<analysis-id>&p=<comma-separated-path>`; `p` follows the selected move and browser history is not inflated per move.
- Room codes currently act as bearer-like collaboration links. Do **not** mistake them for future authenticated authorization; adding authentication requires explicit ownership/sharing/permissions policy.
- The stored identity tables are intentionally minimal. `Analysis.Accounts.link_verified/3` and `user_for_verified_identity/2` **do not verify OAuth**: only a trusted OAuth callback should call them with independently validated provider data. `Analysis.UserLibrary` is also a domain API, **not an authorization boundary**. Keep the HMAC key secret, stable and separate per environment; avoid outputting tokens/subjects in logs.
- Privacy aspiration is **data minimization**, not an assertion of legal anonymity: provider subjects hashed with an HMAC are pseudonymous identifiers; imported PGN metadata and user-supplied content can contain people's names. Review retention, logging and provider scopes accordingly.
- Authentication, revocable sessions, a private library/editor and Google/Lichess linking are implemented. Lichess import, stored provider grants and room ownership permissions remain **planned work**. Distinguish tested implementation from confirmed deployment in docs/HANDOFF.md.

## Production and delivery

- Fly.io app `openchesslab`; `openchesslab.com` canonical, `www` redirect; one app machine in **AMS** at handoff. Fly Managed PostgreSQL is the primary DBMS, release migrations run through `OpenChessLab.Database.Release.migrate/0` (see `fly.toml`). `/health` and `/ready` are health checks.
- Explicit deployment command, only when requested: `flyctl deploy --remote-only -a openchesslab`. Useful checks: `flyctl checks list -a openchesslab`, `flyctl machine list -a openchesslab`.
- The historical two-region Horde owner/replica + DETS/disk store implementation was removed during the PostgreSQL cutover. Do not resurrect it. Horde remains for **room process coordination**, not for owning primary data.
- For detailed historical design choices, observed benchmark fixtures, measured results and verified commits, read [`docs/development-history.md`](docs/development-history.md). Update the docs when a slice changes an established architectural fact or decision; do not duplicate detailed explanations across documents.
