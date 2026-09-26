# Contributing to dwar

This guide covers local setup, verification commands, CI, and the branch/PR
workflow. The [README](README.md) covers usage; [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
covers design and stability contracts.

## Prerequisites

- Ruby `>= 3.2` (see `.ruby-version` for the pinned dev version; CI tests
  3.2, 3.3, 3.4)
- Bundler; SQLite3 (the dummy app's dev/test database — a dev dependency only,
  never a gemspec runtime dependency)
- The dummy app's `schema.rb` is intentionally uncommitted (see `.gitignore`),
  so the test database is always built from migrations (below).

## Setup

Run from the gem root (`dwar/` — every command below assumes this cwd):

```sh
bundle install
bundle exec rake dummy:test_db   # RAILS_ENV=test bin/rails db:create db:migrate via the dummy app
```

`rake dummy:test_db` is the `dummy:test_db` rake task (see `Rakefile`):
it delegates to the dummy app with `ENGINE_ROOT` set so the engine's own
`db/migrate` is registered on the host app. `rake test` depends on it, so a
plain `bundle exec rake test` also prepares the database first. The dummy
app's `schema.rb` and `*.sqlite3` files are gitignored and built from
migrations by this step — a fresh clone has no database until you run it.

To boot the dummy app for manual verification (admin UI at `/dwar`, picker
demo at `/user_picker_demo`), also from the gem root:

```sh
bundle exec bin/rails server   # runs in the dummy app context
```

## Verification commands

Run from the gem root:

```sh
bundle exec rake test    # full Minitest suite (prepares the test DB first; the default rake task)
bundle exec standardrb   # linter (config: .standard.yml, ruby_version 3.2)
```

Both must be green before opening a PR. Per-task PRs should also show the
focused test files run, not just the suite result. Never state a check passed
without running it; if a check cannot run in your environment, report that
explicitly.

Matrix checks (what CI runs per cell):

```sh
BUNDLE_GEMFILE=gemfiles/rails_7.1.gemfile bundle exec rake test
BUNDLE_GEMFILE=gemfiles/rails_7.2.gemfile bundle exec rake test
BUNDLE_GEMFILE=gemfiles/rails_8.0.gemfile bundle exec rake test
```

The variant lockfiles (`gemfiles/*.gemfile.lock`) are committed so installs
are frozen and deterministic.

## CI

`.github/workflows/ci.yml` runs on every push to `main` and every PR:

- `test` — `bundle exec rake test` across Ruby 3.2/3.3/3.4 × Rails 7.1/7.2/8.0
  (each cell selects its gemfile via `BUNDLE_GEMFILE`), with bundler caching.
- `lint` — `bundle exec standardrb` on Ruby 3.4.

## Branch / PR workflow (one task → one branch → one PR)

`main` is the single protected integration branch. Never commit to it directly.

1. Branch from the latest `main`:
   `feat/<ticket>-<short-description>` (or `fix/`, `chore/`, `refactor/`,
   `docs/` — e.g. `docs/T16-documentation`).
2. Keep the change small and scoped to the ticket. Do not bundle unrelated
   improvements; file a separate task for those instead.
3. Add or update tests for the behavior introduced (expected behavior, edge
   cases, failure modes); add a regression test for bug fixes.
4. Commit with conventional messages referencing the ticket (e.g.
   `feat: add percentage rollout evaluation` + `Refs T05`). No AI co-author
   signatures.
5. Push the branch and open a PR targeting `main` titled
   `<TICKET-ID> — <Notion task title>`, with the PR description linking the
   Notion task and covering summary, testing, and follow-ups. Do not merge
   your own PR unless explicitly authorized.

## Docs-sync rule

Documentation is part of implementation. When behavior, APIs, or configuration
change, update the affected docs in the same PR:

- `README.md` (quickstart + configuration reference),
- `docs/ARCHITECTURE.md` (contracts: bucketing scheme, evaluation order,
  cache invalidation, fail-closed authorization, audit semantics),
- `config/initializers` guidance via `lib/generators/dwar/install/templates/dwar.rb`
  (the generated initializer must agree with the README — treat drift as a bug).

Docs-only changes (like this guide) touch no `lib/`, `app/`, `config/`, `db/`,
`test/`, or CI code, and never add docs to the gemspec `files` whitelist.
