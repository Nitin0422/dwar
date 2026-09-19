# dwar — Task Breakdown (DRAFT for review)

**Project:** feature-flags-engine · **Gem:** `dwar` · **Namespace:** `Dwar`
**PRD:** `docs/prd.md` — Approved (2026-09-19)
**Status:** Draft — decisions confirmed (2026-09-19); awaiting explicit Phase 2 approval. Nothing in Notion has been created yet.

---

## 1. Product summary

`dwar` is a reusable, open-source, mountable Rails engine (gem) giving host Rails
applications managed feature flags: full enable/disable, deterministic
percentage rollouts, and group-based user targeting — administered through a
server-rendered Rails-Admin-style web UI and queried through a simple developer
API (`Dwar.enabled?(:key, actor = nil)`).

Learning/portfolio build: polished, idiomatic, well-tested recreation of the
category's fundamentals. Marker of scope: Must Have + Should Have (caching,
authorization hook, audit trail, flag search) are delivered in this effort.
Nice-to-haves (YAML import/export, per-environment overrides, admin UI polish)
are deliberately excluded from the initial breakdown.

## 2. Task overview (17 tasks)

| ID | Task | Key deps |
|----|------|----------|
| T01 | Set up gem scaffolding and pin the support matrix | — |
| T02 | Bootstrap the mountable engine with a dummy app | T01 |
| T03 | Build the data model (migrations + models) | T02 |
| T04 | Implement the configuration surface | T01 |
| T05 | Implement deterministic percentage bucketing | T01 |
| T06 | Implement the evaluation API (`Dwar.enabled?`) | T03, T04, T05 |
| T07 | Implement in-process caching with write invalidation | T06 |
| T08 | Build the admin UI shell (routes, base controller, fail-closed authorization) | T02, T04 |
| T09 | Build the flags admin screens (CRUD + search/filter) | T03, T08 |
| T10 | Build the groups admin screens (CRUD) | T03, T08 |
| T11 | Build the user picker endpoint + autocomplete | T04, T08 |
| T12 | Build the group membership admin screen | T10, T11 |
| T13 | Add the audit trail (model, recording, admin view) | T12 |
| T14 | Build the install generator | T03, T04 |
| T15 | Set up the CI pipeline | T02 |
| T16 | Write documentation (README, architecture, contributor guide) | T09, T10, T12, T13, T14, T15 |
| T17 | Package and publish the gem to RubyGems | T16 |

## 3. Dependency spine and implementation order

Suggested implementation order is T01 → T02 → T03 → T04 → T05 → T06 → T07 →
T08 → T09 → T10 → T11 → T12 → T13 → T14 → T15 → T16 → T17 (parallelize where
dependencies allow).

```text
Evaluation spine:        T01 → T02 → T03 ─┐
                         T01 → T04 ───────┼→ T06 → T07
                         T01 → T05 ───────┘
Admin spine:             T02 + T04 → T08 → T09 / T10 / T11 → T12 → T13
Delivery spine:          T03 + T04 → T14 ; T02 → T15 ; T15 → T16 → T17
```

- **First unblocked task:** T01.
- **Unblocked after T01:** T02, T04, T05, T15.
- **High-leverage tasks (schedule early):** T01 (everything depends on it),
  T05 (pure bucketing logic, unblocks the evaluation core), T03 (data model,
  unblocks T06 and all admin screens), T08 (unblocks every admin screen).

---

## T01 — Set up gem scaffolding and pin the support matrix

**Description**

Create the `dwar` gem skeleton: gemspec, Gemfile, Rakefile with a `test` task,
`lib/dwar.rb` and `lib/dwar/version.rb`, MIT license, `.gitignore`, `.ruby-version`,
std-format lint configuration, and an empty-but-passing test entrypoint. Pin the
Rails/Ruby support matrix decided in technical planning. Initialize the git
repository (the project folder is not yet a repo).

**Acceptance criteria**

- [ ] `dwar.gemspec` exists with: name `dwar`, summary/description matching the
      PRD product summary, MIT license, `files` limited to packaged content,
      homepage/source metadata, and Ruby/Rails constraints (`rails >= 7.1`,
      `ruby >= 3.2`).
- [ ] `require "dwar"` loads and exposes the `Dwar` module and `Dwar::VERSION`.
- [ ] Gemfile, Rakefile (`rake test` default task), MIT `LICENSE.txt`,
      `.gitignore` (gem/temp artifacts, editor cruft, dummy log/tmp),
      `.ruby-version` are present and consistent.
- [ ] Lint tooling configured (default: `standardrb`) and runs clean on the
      scaffold.
- [ ] `bundle exec rake test` exits 0 (trivial placeholder suite).
- [ ] Git repository initialized with the scaffold committed; no secrets or
      local credentials in the tree.
- [ ] Support matrix recorded in the gemspec and (in T15) CI: Rails >= 7.1
      (7.1, 7.2, 8.0) × Ruby >= 3.2 (3.2, 3.3, 3.4).

**Dependencies:** none.

**Technical considerations**

- Created via `rails plugin new dwar --mountable --skip-test --dummy-path=test/dummy`
  and then pruned/configured; the mountable flag is relevant to T02.
- Standardrb chosen as the default linter (family standard); swap for rubocop
  only if the manager prefers it.
- GitHub remote creation is not a code task; it happens at PR time as part of
  the normal workflow.

**Testing requirements**

- `ruby -Ilib -e 'require "dwar"; puts Dwar::VERSION'` prints a version.
- `bundle exec rake test` and the configured linter pass.

---

## T02 — Bootstrap the mountable engine with a dummy app

**Description**

Turn the scaffold into a working mountable engine: `lib/dwar/engine.rb` with
`Dwar::Engine < Rails::Engine` and `isolate_namespace Dwar`, a runnable dummy
Rails app under `test/dummy` (development/manual verification per PRD §6-9),
test wiring (`test_helper`, fixture dir, db config) so tests run from the gem
root in both `test` and `development`.

**Acceptance criteria**

- [ ] `Dwar::Engine` is defined under `lib/dwar/`, uses `isolate_namespace Dwar`,
      and is autoloadable per Rails engine conventions.
- [ ] Dummy app boots: `bin/rails runner "puts Dwar::VERSION"` (dummy context)
      succeeds against the dummy database.
- [ ] Test infrastructure wired: `bundle exec rake test` (gem root) runs the
      Minitest suite against the dummy app and a trivial engine test passes.
- [ ] Dummy app scripts/config (Rakefile stub, `test/dummy/config/*`,
      `app/views/layouts/dwar` placeholder if generated) are pruned to the
      minimal set needed.
- [ ] Naming isolation confirmed: no host-app constant is patched by the engine.

**Dependencies:** T01.

**Technical considerations**

- `isolate_namespace` gives `Dwar::` prefixed models/controllers/helpers and
  isolated view paths; table prefixing itself lands in T03.
- Fixtures live in `test/dummy` per Rails engine convention; keep the schema
  owned by migrations (T03), not `schema.rb` drift.
- The dummy app is **committed to and maintained in this repository**
  (`test/dummy`) per Rails engine convention — it is the engine's test harness
  and example host, versioned alongside the engine. It is distinct from the
  scratch host app used in T17's published-gem smoke test (which simulates an
  external consumer). The dummy app is not packaged into the built gem
  (gemspec `files` whitelist excludes it), and it is kept in sync as later
  tasks add migrations, routes, and configuration.

**Testing requirements**

- Dummy boot smoke test; a placeholder engine unit test (e.g., `Dwar::VERSION`
  present) executes through the rake test task.

---

## T03 — Build the data model (migrations + models)

**Description**

Migrations and models for the four tables: `dwar_flags` (unique key, state,
percentage), `dwar_groups` (unique name, optional description),
`dwar_flag_groups` (join: flag ↔ targeted groups), `dwar_group_memberships`
(polymorphic actor reference). Models: `Dwar::Flag`, `Dwar::Group`,
`Dwar::FlagGroup`, `Dwar::GroupMembership` with validations, associations, and
the flag state enum. All internals namespaced under `Dwar::` with `dwar_`
table prefixes (FR-9).

**Acceptance criteria**

- [ ] Migrations create all four tables with the `dwar_` prefix, foreign keys,
      and indexes: unique index on `dwar_flags.key`; unique index on
      `dwar_groups.name`; unique compound index on
      `dwar_flag_groups(flag_id, group_id)`; unique compound index on
      `dwar_group_memberships(group_id, actor_type, actor_id)`.
- [ ] Migrations are reversible (up/down) and run cleanly in the dummy app.
- [ ] `Flag` has: `key` (presence, uniqueness, sensible format e.g. `\A[a-z0-9_/.-]+\z`),
      state enum `disabled | enabled | percentage | groups | groups_and_percentage`,
      `percentage` integer 0–100 validated to be present/range-checked where the
      state uses it.
- [ ] `Group` has `name` (presence, uniqueness) and optional `description`.
- [ ] `FlagGroup` validates uniqueness of (flag, group); `Flag` ↔ `Group`
      many-to-many via the join; destroy of a flag/group cleans up join rows.
- [ ] `GroupMembership` stores polymorphic `actor_type`/`actor_id`
      (`belongs_to :actor, polymorphic: true`), validates uniqueness per
      (group, actor), and requires a stable `id` on actors (FR-10 constraint:
      actors expose a stable id).
- [ ] No model monkey-patches host classes; everything is `Dwar::*`.

**Dependencies:** T02.

**Technical considerations**

- Explicit `self.table_name = "dwar_..."` per model (or `Dwar.table_name_prefix`)
  — pick one and stay consistent.
- State modeled as a Rails enum (string-backed) for clarity; `percentage`
  defaults to 0 and is only meaningful for `percentage` and
  `groups_and_percentage` states.
- Aim for a single migration to create the schema in the dummy app; the
  install generator (T14) packages these migrations for host apps.

**Testing requirements**

- Model unit tests: validations (key/name presence+uniqueness+format,
  percentage range), associations, join-row cleanup on destroy, membership
  polymorphic references and uniqueness.
- Migration up/down verified in the dummy app.

---

## T04 — Implement the configuration surface

**Description**

`Dwar.configure { |c| ... }` and `Dwar.config` exposing the PRD (FR-11) options:
`user_finder` (required for the picker), `user_display` (default `to_s`),
`admin_path` (default `/dwar`), `authorization` hook (default nil → denied),
`cache` toggle (default on), and `audit_actor` (optional, added with T13).

**Acceptance criteria**

- [ ] `Dwar.configure` yields a `Dwar::Configuration` object; `Dwar.config`
      returns the populated config; defaults match the PRD.
- [ ] `user_display` defaults to `to_s` (used when rendering members).
- [ ] `admin_path` defaults to `/dwar`; authorization defaults to nil
      (fail closed, FR-10); cache defaults to enabled.
- [ ] Missing `user_finder` raises a clear, descriptive error **only when the
      picker endpoint is exercised** (T11), not at boot.

**Dependencies:** T01.

**Technical considerations**

- Plain `attr_accessor`s on `Dwar::Configuration`; frozen default instance to
  avoid cross-app state leaks; document every option (surfaced again in T16).
- The authorization and audit hooks are callables evaluated in the admin
  controller context (see T08/T13).

**Testing requirements**

- Unit tests: defaults, custom overrides, config isolation between configure
  blocks, error behavior for the unset `user_finder`.

---

## T05 — Implement deterministic percentage bucketing

**Description**

Pure bucketing module (e.g., `Dwar::Bucketing.bucket(flag_key, actor_class, actor_id)`)
returning an integer in `0...100`, derived from a stable hash of
(flag key, actor class, actor id) per FR-4. Same actor + flag always resolves
identically across requests; changing the percentage only shifts the cutoff.

**Acceptance criteria**

- [ ] `bucket(flag_key, actor_class, actor_id)` returns an integer in `0..99`.
- [ ] Determinism: identical inputs produce identical buckets on repeated
      calls and across Ruby processes/versions (hash is not `Object#hash` /
      not `String#hash`; use a stable digest, e.g., SHA-256 of the tuple).
- [ ] Distribution sanity: a statistical smoke over many actors shows
      roughly uniform spread (no catastrophic clustering) — verified by a test
      with broad bounds, not a flaky exact assertion.
- [ ] Distinct actors and distinct flags generally produce different buckets;
      the tuple is order-sensitive (`flag|class|id`).
- [ ] Actor `id` may be integer or string; `actor_class` is a string/class
      name — both are normalized consistently so `User` and `"User"` map identically.

**Dependencies:** T01.

**Technical considerations**

- Document the hash input contract in code: it is part of the public stability
  promise — once released, the tuple format must not change or every rollout
  re-buckets.
- Boundary math lands in T06 (`bucket < percentage` ⇒ enabled; at 100% all
  actors pass because max bucket is 99).

**Testing requirements**

- Unit tests: determinism (repeat calls), range 0–99, distinctness of a few
  known tuples, normalization of class name/id types, uniform-spread smoke.

---

## T06 — Implement the evaluation API (`Dwar.enabled?`)

**Description**

Public API `Dwar.enabled?(:key, actor = nil)` implementing FR-3 resolution:

1. Flag disabled → `false`.
2. Flag fully enabled → `true`.
3. Percentage-only → `true` iff actor supplied and `bucket(actor) < percentage`;
   no actor → `false`.
4. Group-targeted → `true` iff actor belongs to a targeted group and (when a
   percentage is set) `bucket(actor) < percentage`.
5. Unknown flag key → `false` (never raises).

**Acceptance criteria**

- [ ] Every FR-3 rule is implemented in order and covered by a test.
- [ ] `percentage` states require an actor to return true (per PRD §13).
- [ ] `groups_and_percentage` combines membership + bucket.
- [ ] Unknown keys and missing flags return `false` without raising, for both
      signatures (`enabled?(:key)` and `enabled?(:key, user)`).
- [ ] Percentage boundaries: 0% → everyone false; 100% → every actor with a
      stable id true; 99 vs 100 edge covered.
- [ ] Uses T05 bucketing (no duplicated hash logic).

**Dependencies:** T03, T04, T05.

**Technical considerations**

- Keep evaluation queries simple per call (flag lookup, membership lookup);
      the caching task (T07) removes per-request DB cost, per PRD §11.
- Membership lookup: actor is in the group set iff a
      `GroupMembership` row exists for any targeted group with matching
      `actor_type`/`actor_id`.

**Testing requirements**

- Table-driven unit tests over all states × actor present/absent × membership
  present/absent × boundary percentages; unknown-key tests; ever-green
  100% case with a variety of actors.

---

## T07 — Implement in-process caching with write invalidation

**Description**

Per-process cache for evaluation results with write invalidation (Should Have,
confirmed in PRD §10). Config toggle (`Dwar.config.cache`, default on). Writes
to flags, groups, targeting (flag↔group join), or memberships invalidate so the
next evaluation reflects the change immediately (FR-8).

**Acceptance criteria**

- [ ] Repeated `enabled?` calls for the same (flag, actor) within the process
      hit the cache after the first evaluation (verifiable via an
      instrumented miss counter in tests).
- [ ] Creation/update/deletion of a flag, its targeting, a group, or a
      membership invalidates the affected entries; a disable→enable flip (and
      every other state change) is observed by the next `enabled?` call with no
      restart (FR-8).
- [ ] Invalidation uses `after_commit` hooks (no writes on rollback).
- [ ] Toggle off → no caching (each call re-evaluates).
- [ ] Basic thread-safety for the in-process store; keys versioned so a
      rollback never serves stale data indefinitely.
- [ ] Cache never changes semantics: results equal uncached results at every
      step of the tests above.

**Dependencies:** T06.

**Technical considerations**

- Simple scheme: an in-memory store + a global “generation” counter bumped on
      any relevant write, plus a per-flag version for finer-grained invalidation;
      cache keys embed the generation(s). Coarse-and-correct beats clever.
- Toggle default on; document performance expectation in the dummy app
      (un-cached evaluation is single-digit-ms DB lookups; cached is ~0).

**Testing requirements**

- Instrumented cache-hit/miss tests; write-then-re-evaluate freshness tests for
      every mutation path; toggle tests; equivalence with uncached results.

---

## T08 — Build the admin UI shell (routes, base controller, fail-closed authorization)

**Description**

Admin area skeleton: engine routes (`root` → flags index, flags, groups,
membership, picker search endpoint — bodies in T09–T12), a namespaced base
controller with the authorization before_action (FR-10: fail closed, hook
configured via T04; default deny), and a minimal shared layout/stylesheet
(server-rendered, no build step per PRD §10).

**Acceptance criteria**

- [ ] Engine routes are defined and mountable; admin reachable at the host's
      mount path (default `/dwar`, per FR-1 instruction).
- [ ] With no `authorization` hook configured, every admin route denies access
      (fail closed) — e.g., 403 + clear message; no admin action is reachable.
- [ ] With a hook configured to return true, routes are reachable; the hook is
      evaluated with the controller as context (e.g., can inspect
      `current_user` via host helpers).
- [ ] Route namespaces/controllers/helpers are `Dwar::`-scoped (FR-9).
- [ ] Layout renders minimal brand/stylesheet; placeholder page stubs for each
      admin section mount without error.

**Dependencies:** T02, T04.

**Technical considerations**

- Mounting lives host-side (`mount Dwar::Engine => Dwar.config.admin_path`);
      engine URL helpers adapt automatically to the mount path — the
      initializer/README (T14/T16) instruct this.
- Controllers under `Dwar::Admin::*` (or a `Dwar::ApplicationController`
      base + admin scope) — decide in code, keep consistent.
- Authorization hook shape (assumed): `config.authorization = ->(controller) { ... }`,
      returning truthy to permit. This resolves the PRD §12 open question with
      the simpler option; flag to manager if a Pundit-style adapter is wanted.

**Testing requirements**

- Request tests against the dummy app: deny-without-hook, deny-with-false-hook,
      allow-with-true-hook; route existence/smoke for each stub section.

---

## T09 — Build the flags admin screens (CRUD + search/filter)

**Description**

Flags CRUD (FR-6): index with per-flag state and targeting summary + search
filtering by key/description (Should Have), new/create (default state:
disabled per UF-2), edit/update (state, percentage, targeted groups
multi-select), destroy with confirmation.

**Acceptance criteria**

- [ ] Create flag with key + description → appears on index with state
      "disabled" and evaluates `false` immediately (UF-2).
- [ ] Edit updates state/percentage/targeted groups; validation errors render
      in-line and re-show the form with values preserved.
- [ ] State transitions exercised via UI: enabled, percentage 0–100,
      `groups`, `groups_and_percentage` — persisted and reflected by
      `Dwar.enabled?` on the next call (immediate effect with T07).
- [ ] Index shows each flag's state and a targeting summary (percentage value,
      targeted group names).
- [ ] Search filters the index by key and description substring without erroring
      on empty results.
- [ ] Destroy removes the flag (and its join rows) with confirmation.

**Dependencies:** T03, T08.

**Technical considerations**

- Server-rendered ERB forms with a multi-select for targeted groups (no SPA).
- Flash messages for success/errors; CSRF protection default (engine inherits
      host policy).

**Testing requirements**

- Request tests per action: CRUD, validation error re-render, search, delete;
  integration: create→evaluate, update-state→evaluate reflects immediately.

---

## T10 — Build the groups admin screens (CRUD)

**Description**

Groups CRUD (FR-6): index (name, description, member count), create/edit/delete
with unique-name validation; deleting a group cleans up memberships and
flag-targeting join rows.

**Acceptance criteria**

- [ ] Index lists groups with name, description, and member count.
- [ ] Create/edit persist name + optional description; duplicate names are
      rejected with a visible validation error.
- [ ] Destroy removes the group, its `GroupMembership` rows, and its
      `FlagGroup` rows; affected flags' targeting no longer resolves true.
- [ ] Changes take effect immediately for subsequent `enabled?` calls
      (FR-8, with T07).

**Dependencies:** T03, T08.

**Testing requirements**

- Request tests for index/create/edit/destroy; duplicate-name and empty-name
  validation; membership-count display; cascade behavior verification.

---

## T11 — Build the user picker endpoint + autocomplete

**Description**

User picker (FR-7): a JSON search endpoint backed by the configured
`user_finder` callable, returning results as `{id, label}` where label comes
from `user_display`; a minimal vanilla-JS autocomplete (the PRD's "autocomplete
only" JS allowance) wired to it. Defensive handling per PRD §11: finder errors
or absence never 500.

**Acceptance criteria**

- [ ] `GET .../users.json?q=<query>` invokes `config.user_finder` with the
      query and returns JSON `[{id, label}, ...]`.
- [ ] Label honors `user_display` (default `to_s` renders `record.to_s`).
- [ ] With `user_finder` unset, the endpoint returns a clear, safe error
      (e.g., 503 with "user_finder not configured") — never a 500 stack.
- [ ] Finder raising an error → endpoint returns empty results + logged
      warning, never a 500.
- [ ] Autocomplete: typing in the picker field triggers the search and offers
      selectable results; no build step, no external JS dependency.

**Dependencies:** T04, T08.

**Technical considerations**

- `user_finder` contract: callable receiving a query string; may return any
      enumerable of objects responding to `id` (and rendered via
      `user_display`). Host apps are told to scope by their own tenant/auth as
      needed (documented in T16).
- Vanilla JS file shipped by the engine (asset-friendly, tiny); keep it to one
      file.

**Testing requirements**

- Request tests: happy path with a stub finder, label mapping incl. custom
  `user_display`, missing-config error, raising-finder fallback; basic
  presence of the autocomplete behavior (JS smoke by inspection/manual in dummy;
  automated if cheap).

---

## T12 — Build the group membership admin screen

**Description**

Per-group membership management (FR-6/FR-7): list members (labels via
`user_display`), add users from the picker (T11), remove users. Stores
polymorphic actor class + id (T03) and keeps evaluation + cache consistent.

**Acceptance criteria**

- [ ] Membership screen lists current members with `user_display` labels.
- [ ] Adding a selected picker result creates a `GroupMembership`
      (actor_type + actor_id, deduped — duplicates rejected).
- [ ] Removing deletes the membership.
- [ ] Add/remove take effect immediately: a group-targeted flag flips for the
      affected actor on the next `enabled?` call (FR-8 + T07 invalidation).
- [ ] A targeted flag with `groups_and_percentage` correctly requires both
      membership and bucket passing.
- [ ] Members whose actor records no longer resolve are rendered defensively
      (label fallback, no crash).

**Dependencies:** T10, T11.

**Testing requirements**

- Request tests: list/add/remove/duplicate; evaluation integration for
  membership add→true, remove→false; missing-actor rendering.

---

## T13 — Add the audit trail (model, recording, admin view)

**Description**

Audit trail (Should Have): `dwar_audits` table recording who/what/when for
flag, group, and membership changes (create/update/destroy incl. targeting
changes); recording happens in the same transaction as the write; a minimal
admin view lists entries newest-first. "Who" comes from an optional
`config.audit_actor` callable evaluated in the admin request context (default
nil → null actor).

**Acceptance criteria**

- [ ] `dwar_audits` migration + model: auditable type/id, action
      (create/update/destroy), change summary (serialized), optional admin
      type/id (who), created_at (when).
- [ ] Every flag create/update/destroy, group create/update/destroy, and
      membership add/remove writes an audit row in the same transaction; flag
      targeting changes are audited as flag updates.
- [ ] `who` recorded when `config.audit_actor` is configured, null otherwise.
- [ ] Audits index page lists entries newest-first with readable action/type/
      key summary.
- [ ] Audit writes never break the underlying operation (failure of recording
      is surfaced, not silently swallowed — decide and document).

**Dependencies:** T12.

**Technical considerations**

- Recording via `after_commit` on the models (or an abstraction invoked by the
      admin controllers — pick the least invasive).
- Keep the “who” contract aligned with the authorization hook (controller
      context) so apps can reuse `current_user`.

**Testing requirements**

- Unit: audit rows created with correct fields per mutation; request: audit
  list renders; configured audit_actor populates who; unconfigured → null.

---

## T14 — Build the install generator

**Description**

`rails generate dwar:install` (FR-1): copies the migrations and generates an
initializer with commented guidance (all T04 options incl. `user_finder`,
`user_display`, `admin_path`, `authorization`, cache toggle) plus a comment
showing the mount line.

**Acceptance criteria**

- [ ] Generator is runnable as `bin/rails generate dwar:install …` in the
      dummy app (and documented for host apps).
- [ ] Copies all four migrations without duplicating on re-run.
- [ ] Generates `config/initializers/dwar.rb` with every configuration option
      commented, defaults matching T04.
- [ ] Output includes the recommended mount path (`mount Dwar::Engine =>
      "/dwar"`).
- [ ] Generator has automated coverage (Rails::Generators::TestCase) asserting
      the created files.

**Dependencies:** T03, T04.

**Testing requirements**

- Generator tests (file creation, idempotency of migration copies); a manual
  run in the dummy app shown working.

---

## T15 — Set up the CI pipeline

**Description**

GitHub Actions workflow running the test suite and lint across the pinned
support matrix (T01): Ruby 3.2/3.3/3.4 × Rails 7.1/7.2/8.0 (Appraisal-style
gemfiles or an equivalent matrix), plus lint. This is the automated enforcer of
the "passing suite" success criterion.

**Acceptance criteria**

- [ ] `.github/workflows/ci.yml` runs `bundle exec rake test` and the linter
      on the matrix; failures are red, successes green.
- [ ] Gemfiles for each Rails version exist and each installs cleanly.
- [ ] CI passes on the current branch when pushed (verified once pushed to
      GitHub).
- [ ] Workflow cached dependencies to keep runs reasonable.

**Dependencies:** T02.

**Testing requirements**

- `appraisal install` + `appraisal rake test` locally for each gemfile; green
  CI run after push.

---

## T16 — Write documentation (README, architecture, contributor guide)

**Description**

Documentation per PRD §6-8: README (quickstart UF-1 + configuration reference
FR-11), architecture overview (namespace, models, evaluation flow, caching,
security), and a contributor/development guide (setup, test, lint, CI, PR
workflow). Quickstart steps must work when followed against the dummy app.

**Acceptance criteria**

- [ ] README quickstart: add gem → run installer (T14) → migrate → mount →
      configure `user_finder` → call `Dwar.enabled?(:key, current_user)`;
      verified end-to-end in the dummy app, including via the published gem
      (cross-checked in T17).
- [ ] Configuration reference documents every T04 option with meaning,
      type, default, and example.
- [ ] Architecture doc covers: namespacing/isolation (FR-9), schema, evaluation
      resolution (FR-3), bucketing contract (FR-4 + T05 stability promise),
      caching + invalidation (T07), authorization fail-closed (FR-10), audit
      (T13), and admin JS footprint.
- [ ] Contributor guide: dev setup, running tests/lint/CI, branch/PR workflow
      aligned with the global AGENTS.md conventions (one task → one branch →
      one PR).
- [ ] Docs match the implemented code (any divergence caught in review).

**Dependencies:** T09, T10, T12, T13, T14, T15.

**Testing requirements**

- Walk the quickstart against the dummy app (and, in T17, a scratch app from
  the published gem); doc accuracy review as part of the PR.

---

## T17 — Package and publish the gem to RubyGems

**Description**

Final step of the success criteria: build a clean `.gem`, publish to RubyGems
under the `dwar` name, and smoke-test integration from a fresh Rails app using
the published gem (quickstart UF-1). Requires human manager authorization and
RubyGems credentials at execution time (release decision — human-owned).

**Acceptance criteria**

- [ ] `gem build dwar.gemspec` produces a clean package (files complete,
      no dev artifacts, version from T01).
- [ ] Gem published to RubyGems and visible with correct metadata (name, MIT,
      homepage/source links, description).
- [ ] Smoke test: a fresh Rails app adds the published gem, runs the installer,
      migrates, mounts, configures `user_finder`, and `Dwar.enabled?`
      resolves correctly (full UF-1 pass against the published artifact).
- [ ] Docs updated with the released version if anything surfaced during the
      smoke test.

**Dependencies:** T16.

**Technical considerations**

- Requires human-provided RubyGems credentials and explicit go-ahead; this task
      is scheduled but awaits authorization before execution.
- Optionally tag the release (e.g., `v0.1.0`) with a matching GitHub release.

**Testing requirements**

- Local gem build/install smoke; fresh-app quickstart run; rubygems.org page
  check post-publish.

---

## 4. Completeness pass (PRD coverage)

| PRD requirement | Task(s) |
|---|---|
| FR-1 integration / install generator / mount at configurable path | T01, T02, T08, T14, T16 |
| FR-2 flag model (key, state, percentage) | T03, T09 |
| FR-3 evaluation resolution (fail closed) | T06 |
| FR-4 deterministic bucketing | T05, T06 |
| FR-5 groups + membership + targeting | T03, T10, T12 |
| FR-6 admin UI (flags/groups/membership CRUD) | T09, T10, T12 |
| FR-7 user picker (`user_finder`, `user_display`) | T04, T11, T12 |
| FR-8 immediate effect (+ cache invalidation) | T07 + write paths (T09, T10, T12) |
| FR-9 namespace isolation / `dwar_` tables | T02, T03 |
| FR-10 security fail-closed authorization | T08 |
| FR-11 single-configuration surface | T04, T14, T16 |
| Should Have: caching | T07 |
| Should Have: authorization hook | T08 |
| Should Have: audit trail | T13 |
| Should Have: flag search/filter | T09 |
| Success criteria: suite + dummy app + docs | everywhere; T02, T16 |
| Success criteria: published to RubyGems | T17 |

Every Must Have and Should Have is covered by at least one task. The three
explicit Nice-to-Haves (YAML import/export, per-environment overrides, admin UI
polish) are intentionally **not** decomposed here — they can be added as
follow-up tasks later without changing the plan.

## 5. Assumptions and confirmed decisions

**Confirmed by human manager (2026-09-19):** items marked ✅ below, plus the
audit trail includes an admin list page (T13), and no task structural changes
are desired (17 tasks as listed).

1. ✅ **Support matrix:** Rails `>= 7.1` (test 7.1, 7.2, 8.0) × Ruby `>= 3.2`
   (test 3.2, 3.3, 3.4) — per PRD §10 proposed minimums.
2. ✅ **Authorization style:** simple callable hook
   `config.authorization = ->(controller) { bool }` evaluated in admin
   controller context; nil → denied. (Option A.)
3. **Audit identity ("who"):** optional `config.audit_actor = ->(controller) { ... }`
   callable, evaluated in request context; nil → null actor. PRD does not
   specify where admin identity comes from. (The audit **does** include a
   minimal admin list page — confirmed.)
4. **Test framework:** Minitest (Rails default) + fixtures in the dummy app.
   Linting: standardrb (can swap to rubocop on request).
5. **Cache default:** ON, with coarse-and-correct invalidation (global +
   per-flag generations), toggleable.
6. **`user_finder` contract:** callable taking a query string, returning any
   enumerable of objects that respond to `id`; rendered via `user_display`;
   errors rescued (empty result + log), never a 500.
7. **Mount path:** host mounts the engine (`mount Dwar::Engine => path`,
   default `/dwar`); engine helpers adapt automatically. `config.admin_path`
   is the documented/expected path.
8. ✅ **Nice-to-haves excluded** from the initial task set (see §4).
9. **T17 publish** requires human RubyGems credentials + explicit go-ahead.

## 6. Items to confirm — resolved (2026-09-19)

- [x] Support matrix — confirmed per PRD (Assumption 1).
- [x] Authorization hook style — Option A, simple callable hook (Assumption 2).
- [x] Audit includes a minimal admin list page (T13).
- [x] Nice-to-Haves deferred (Assumption 8).
- [x] Task structure — no merges/splits; 17 tasks as listed.

Remaining gate: explicit human approval to proceed to Phase 2 (export
`docs/PLAN.md`, create/update the Notion board and the 17 task cards).