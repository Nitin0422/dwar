# dwar — Approved Project Plan

**Project:** feature-flags-engine · **Gem:** `dwar` · **Namespace:** `Dwar`
**PRD:** `docs/prd.md` — Approved (2026-09-19)
**Draft breakdown:** `docs/TASK_PLAN.md`
**Status:** ✅ Approved by human manager (2026-09-19) — 17 tasks finalized.
**Notion board:** Dwar — see §8 for the board URL and per-task card links.

> This document is the finalized, approved plan. It is the authoritative
> implementation order for `dwar`. Notion holds the live workflow state; this
> document holds the approved scope, decisions, and acceptance criteria.

---

## 1. Product summary

`dwar` is a reusable, open-source, mountable Rails engine (gem) giving host
Rails applications managed feature flags: full enable/disable, deterministic
percentage rollouts, and group-based user targeting — administered through a
server-rendered Rails-Admin-style web UI and queried through a simple developer
API (`Dwar.enabled?(:key, actor = nil)`).

Learning/portfolio build: a polished, idiomatic, well-tested recreation of the
category's fundamentals.

**Scope marker:** Must Have + Should Have (caching, authorization hook, audit
trail, flag search) are delivered in this effort. Nice-to-haves (YAML
import/export, per-environment overrides, admin UI polish) are deliberately
excluded and can be added later without changing this plan.

---

## 2. Approved product and technical decisions

Confirmed by the human manager on 2026-09-19:

| # | Decision | Resolution |
|---|----------|------------|
| 1 | Support matrix | Rails `>= 7.1` (CI tests 7.1, 7.2, 8.0) × Ruby `>= 3.2` (CI tests 3.2, 3.3, 3.4) |
| 2 | Authorization style | Option A — simple callable hook `config.authorization = ->(controller) { bool }`; `nil` ⇒ denied (fail closed) |
| 3 | Audit trail | Includes a minimal admin list page (T13) |
| 4 | Nice-to-haves | Deferred; not decomposed |
| 5 | Task structure | No merges/splits — 17 tasks as listed |
| 6 | Dummy app location | Committed and maintained in the main repo at `test/dummy` (standard engine convention) |

Remaining engineering assumptions (not overridden by the manager):

| # | Assumption |
|---|------------|
| 7 | Test framework: Minitest (Rails default) with fixtures in the dummy app |
| 8 | Linting: `standardrb` (swappable to rubocop on request) |
| 9 | Cache default: ON, coarse-and-correct invalidation (global + per-flag generations), toggleable |
| 10 | `user_finder` contract: callable taking a query string → enumerable of objects responding to `id`; rendered via `user_display`; errors rescued (empty result + log), never a 500 |
| 11 | Mount path: host mounts the engine (`mount Dwar::Engine => path`, default `/dwar`); engine helpers adapt automatically |
| 12 | Audit identity: optional `config.audit_actor = ->(controller) { ... }`; `nil` ⇒ null actor |
| 13 | T17 publish requires human RubyGems credentials + explicit go-ahead |

---

## 3. Full task table

| ID | Task | Deps | Primary deliverables |
|----|------|------|---------------------|
| T01 | Set up gem scaffolding and pin the support matrix | — | gemspec, Gemfile, Rakefile, `lib/dwar.rb`, `lib/dwar/version.rb`, LICENSE, `.gitignore`, `.ruby-version`, lint config, git repo |
| T02 | Bootstrap the mountable engine with a dummy app | T01 | `Dwar::Engine` (`isolate_namespace`), runnable `test/dummy`, test wiring |
| T03 | Build the data model (migrations + models) | T02 | `dwar_flags`, `dwar_groups`, `dwar_flag_groups`, `dwar_group_memberships` + `Dwar::*` models |
| T04 | Implement the configuration surface | T01 | `Dwar.configure` / `Dwar.config` / `Dwar::Configuration` |
| T05 | Implement deterministic percentage bucketing | T01 | `Dwar::Bucketing.bucket(flag_key, actor_class, actor_id)` |
| T06 | Implement the evaluation API (`Dwar.enabled?`) | T03, T04, T05 | `Dwar.enabled?(:key, actor = nil)` implementing FR-3 |
| T07 | Implement in-process caching with write invalidation | T06 | Evaluation cache + generation-based invalidation |
| T08 | Build the admin UI shell (routes, base controller, fail-closed authorization) | T02, T04 | Engine routes, admin base controller, authorization before_action, layout |
| T09 | Build the flags admin screens (CRUD + search/filter) | T03, T08 | Flags index/new/create/edit/update/destroy + search |
| T10 | Build the groups admin screens (CRUD) | T03, T08 | Groups index/new/create/edit/update/destroy |
| T11 | Build the user picker endpoint + autocomplete | T04, T08 | JSON search endpoint + vanilla-JS autocomplete |
| T12 | Build the group membership admin screen | T10, T11 | Membership list/add/remove |
| T13 | Add the audit trail (model, recording, admin view) | T12 | `dwar_audits` + recording + admin index |
| T14 | Build the install generator | T03, T04 | `rails generate dwar:install` |
| T15 | Set up the CI pipeline | T02 | `.github/workflows/ci.yml` + Appraisal gemfiles |
| T16 | Write documentation (README, architecture, contributor guide) | T09, T10, T12, T13, T14, T15 | README, architecture doc, contributor guide |
| T17 | Package and publish the gem to RubyGems | T16 | Published gem + fresh-app smoke test |

---

## 4. Dependency-honoring implementation order

```text
Recommended order: T01 → T02 → T03 → T04 → T05 → T06 → T07 → T08 → T09 →
                   T10 → T11 → T12 → T13 → T14 → T15 → T16 → T17
(parallelize wherever dependencies allow)
```

```text
Evaluation spine:  T01 → T02 → T03 ─┐
                   T01 → T04 ───────┼→ T06 → T07
                   T01 → T05 ───────┘
Admin spine:       T02 + T04 → T08 → T09 / T10 / T11 → T12 → T13
Delivery spine:    T03 + T04 → T14 ; T02 → T15 ; T15 → T16 → T17
```

- **First unblocked task:** T01.
- **Unblocked after T01:** T02, T04, T05, T15.
- **High-leverage tasks (schedule early):** T01 (everything depends on it),
  T05 (pure bucketing logic, unblocks the evaluation core), T03 (data model,
  unblocks T06 and all admin screens), T08 (unblocks every admin screen).

---

## 5. Per-task requirements, acceptance criteria, and testing

Per-task detail is mirrored on the corresponding Notion card (§8). The
approved acceptance criteria are reproduced below; each Notion card carries the
same criteria plus description, dependencies, technical considerations, and
testing requirements.

### T01 — Set up gem scaffolding and pin the support matrix

**Requirements:** Create the gem skeleton (gemspec, Gemfile, Rakefile with a
`test` task, `lib/dwar.rb`, `lib/dwar/version.rb`, MIT license, `.gitignore`,
`.ruby-version`, lint config, placeholder suite) and initialize the git
repository.

**Acceptance criteria**
- [ ] `dwar.gemspec`: name `dwar`, PRD-matching summary/description, MIT license, `files` limited to packaged content, homepage/source metadata, `rails >= 7.1`, `ruby >= 3.2`.
- [ ] `require "dwar"` exposes `Dwar` and `Dwar::VERSION`.
- [ ] Gemfile, Rakefile (`rake test` default), `LICENSE.txt`, `.gitignore`, `.ruby-version` present and consistent.
- [ ] Lint tooling configured (default `standardrb`) and clean on the scaffold.
- [ ] `bundle exec rake test` exits 0 with a placeholder suite.
- [ ] Git repo initialized, scaffold committed, no secrets in the tree.
- [ ] Support matrix recorded (gemspec now; CI in T15).

**Testing:** `ruby -Ilib -e 'require "dwar"; puts Dwar::VERSION'`; `bundle exec rake test`; linter run.

### T02 — Bootstrap the mountable engine with a dummy app

**Requirements:** `lib/dwar/engine.rb` with `Dwar::Engine < Rails::Engine` and
`isolate_namespace Dwar`; a runnable dummy app under `test/dummy`; test wiring
so the suite runs from the gem root.

**Acceptance criteria**
- [ ] `Dwar::Engine` defined, uses `isolate_namespace Dwar`, autoloadable per engine conventions.
- [ ] Dummy app boots (`bin/rails runner "puts Dwar::VERSION"`).
- [ ] `bundle exec rake test` runs Minitest against the dummy app; a trivial engine test passes.
- [ ] Dummy app config/scripts pruned to the minimal set needed.
- [ ] No host-app constant patched by the engine.

**Technical considerations:** `isolate_namespace` gives `Dwar::`-prefixed
models/controllers/view paths; table prefixing lands in T03. Fixtures live in
`test/dummy`; schema owned by migrations, not `schema.rb` drift. **The dummy app
is committed to and maintained in this repository** — it is the engine's test
harness and example host, versioned alongside the engine, distinct from the
scratch host app used in T17's published-gem smoke test. It is not packaged
into the built gem, and it is kept in sync as later tasks add migrations,
routes, and configuration.

**Testing:** Dummy boot smoke test; placeholder engine unit test through the rake task.

### T03 — Build the data model (migrations + models)

**Requirements:** Four tables — `dwar_flags` (key, state, percentage),
`dwar_groups` (name, description), `dwar_flag_groups` (flag↔group join),
`dwar_group_memberships` (polymorphic actor) — plus `Dwar::Flag`,
`Dwar::Group`, `Dwar::FlagGroup`, `Dwar::GroupMembership`.

**Acceptance criteria**
- [ ] Migrations create all four `dwar_`-prefixed tables with FKs and indexes: unique `dwar_flags.key`; unique `dwar_groups.name`; unique compound `dwar_flag_groups(flag_id, group_id)`; unique compound `dwar_group_memberships(group_id, actor_type, actor_id)`.
- [ ] Migrations reversible; run cleanly in the dummy app.
- [ ] `Flag`: `key` presence/uniqueness/format (`\A[a-z0-9_/.-]+\z`); state enum `disabled | enabled | percentage | groups | groups_and_percentage`; `percentage` integer 0–100 validated where used.
- [ ] `Group`: `name` presence/uniqueness; optional `description`.
- [ ] `FlagGroup` unique per (flag, group); `Flag` ↔ `Group` many-to-many; destroy cleans up join rows.
- [ ] `GroupMembership`: polymorphic `belongs_to :actor`; unique per (group, actor); actors must expose a stable `id` (FR-10).
- [ ] No model monkey-patches host classes; everything `Dwar::*`.

**Technical considerations:** Explicit `self.table_name` per model (or
`Dwar.table_name_prefix`) — pick one and stay consistent. String-backed enum for
state. Aim for a single migration; T14 packages it for hosts.

**Testing:** Model unit tests (validations, associations, join cleanup, membership uniqueness); migration up/down in the dummy app.

### T04 — Implement the configuration surface

**Requirements:** `Dwar.configure { |c| ... }` and `Dwar.config` exposing FR-11
options: `user_finder`, `user_display` (default `to_s`), `admin_path` (default
`/dwar`), `authorization` (default nil → denied), `cache` (default on), and
`audit_actor` (used in T13).

**Acceptance criteria**
- [ ] `Dwar.configure` yields a `Dwar::Configuration`; `Dwar.config` returns it; defaults match the PRD.
- [ ] `user_display` defaults to `to_s`.
- [ ] `admin_path` defaults to `/dwar`; authorization defaults nil (fail closed); cache defaults enabled.
- [ ] Missing `user_finder` raises a clear error only when the picker is exercised (T11), not at boot.

**Testing:** Unit tests for defaults, overrides, config isolation between configure blocks, and unset-`user_finder` error behavior.

### T05 — Implement deterministic percentage bucketing

**Requirements:** Pure bucketing module
`Dwar::Bucketing.bucket(flag_key, actor_class, actor_id)` → integer `0...100`
from a stable digest of the tuple (FR-4).

**Acceptance criteria**
- [ ] Returns an integer in `0..99`.
- [ ] Deterministic across repeated calls and separate Ruby processes/versions (stable digest such as SHA-256 of the tuple; not `Object#hash`/`String#hash`).
- [ ] Distribution smoke test shows roughly uniform spread with broad bounds (not flaky exact assertions).
- [ ] Distinct actors/flags generally differ; tuple is order-sensitive (`flag|class|id`).
- [ ] `User` and `"User"` normalize identically; integer and string ids normalize consistently.

**Technical considerations:** The hash input contract is part of the public
stability promise — document it in code; it must not change post-release or
every rollout re-buckets. Boundary math (`bucket < percentage`) lands in T06.

**Testing:** Determinism, range, known-tuple distinctness, type normalization, uniform-spread smoke.

### T06 — Implement the evaluation API (`Dwar.enabled?`)

**Requirements:** Public `Dwar.enabled?(:key, actor = nil)` implementing FR-3:
disabled ⇒ false; enabled ⇒ true; percentage-only ⇒ true iff actor supplied and
`bucket(actor) < percentage` (no actor ⇒ false); group-targeted ⇒ true iff
membership and (when a percentage is set) bucket passes; unknown key ⇒ false,
never raises.

**Acceptance criteria**
- [ ] Every FR-3 rule implemented in order and covered by a test.
- [ ] `percentage` states require an actor to return true.
- [ ] `groups_and_percentage` combines membership + bucket.
- [ ] Unknown/missing flags return `false` without raising for both signatures.
- [ ] Boundaries: 0% ⇒ all false; 100% ⇒ every actor with a stable id true; 99 vs 100 edge covered.
- [ ] Reuses T05 bucketing (no duplicated hash logic).

**Testing:** Table-driven tests across all states × actor present/absent × membership present/absent × boundary percentages; unknown-key tests; 100% variety-of-actors case.

### T07 — Implement in-process caching with write invalidation

**Requirements:** Per-process cache of evaluation results with write
invalidation (Should Have; PRD §10). Toggle via `Dwar.config.cache` (default
on). Writes to flags, groups, targeting, or memberships invalidate immediately
(FR-8).

**Acceptance criteria**
- [ ] Repeated `enabled?` calls hit the cache after the first evaluation (instrumented miss counter).
- [ ] Create/update/delete of a flag, its targeting, a group, or a membership invalidates affected entries; a disable→enable flip is observed by the next call with no restart.
- [ ] Invalidation uses `after_commit` hooks (no writes on rollback).
- [ ] Cache off ⇒ each call re-evaluates.
- [ ] Thread-safe in-process store; keys versioned so a rollback never serves stale data indefinitely.
- [ ] Cache never changes semantics: cached results equal uncached results in every test above.

**Technical considerations:** In-memory store + global generation counter bumped
on relevant writes, plus a per-flag version for finer granularity; cache keys
embed the generation(s). Coarse-and-correct beats clever.

**Testing:** Instrumented hit/miss tests; write-then-re-evaluate freshness for every mutation path; toggle tests; cached/uncached equivalence.

### T08 — Build the admin UI shell (routes, base controller, fail-closed authorization)

**Requirements:** Engine routes (root → flags index; flags, groups, membership,
picker — bodies in T09–T12), a namespaced base controller with the authorization
`before_action` (FR-10: fail closed; default deny), and a minimal shared layout
and stylesheet (server-rendered, no build step).

**Acceptance criteria**
- [ ] Engine routes mountable; admin reachable at the host mount path (default `/dwar`).
- [ ] With no `authorization` hook, every admin route denies access (e.g., 403 with a clear message).
- [ ] With a hook returning true, routes are reachable; the hook is evaluated with the controller as context.
- [ ] Routes/controllers/helpers are `Dwar::`-scoped (FR-9).
- [ ] Minimal layout renders; placeholder stubs for each section mount without error.

**Technical considerations:** Mounting is host-side (`mount Dwar::Engine =>
Dwar.config.admin_path`); engine URL helpers adapt to the mount path.
Controllers under `Dwar::Admin::*`. Authorization hook shape:
`config.authorization = ->(controller) { ... }` returning truthy to permit.

**Testing:** Request tests against the dummy app: deny-without-hook, deny-with-false-hook, allow-with-true-hook; route smoke for each stub section.

### T09 — Build the flags admin screens (CRUD + search/filter)

**Requirements:** Flags CRUD (FR-6): index with per-flag state and targeting
summary plus search by key/description (Should Have); new/create (default state
disabled per UF-2); edit/update (state, percentage, targeted groups);
destroy with confirmation.

**Acceptance criteria**
- [ ] Create flag with key + description ⇒ appears on index as disabled and evaluates `false` immediately (UF-2).
- [ ] Edit updates state/percentage/targeted groups; validation errors render in-line with values preserved.
- [ ] All five states exercised via UI and reflected by `Dwar.enabled?` on the next call (immediate effect with T07).
- [ ] Index shows state and a targeting summary (percentage value, targeted group names).
- [ ] Search filters by key and description substring, tolerating empty results.
- [ ] Destroy removes the flag and its join rows, with confirmation.

**Testing:** Request tests per action (CRUD, validation re-render, search, delete); integration create→evaluate and update-state→evaluate.

### T10 — Build the groups admin screens (CRUD)

**Requirements:** Groups CRUD (FR-6): index (name, description, member count),
create/edit/delete with unique-name validation; deleting a group cleans up
memberships and flag-targeting join rows.

**Acceptance criteria**
- [ ] Index lists groups with name, description, and member count.
- [ ] Create/edit persist name + optional description; duplicate names rejected with a visible error.
- [ ] Destroy removes the group, its memberships, and its flag-targeting rows; affected flags stop resolving true.
- [ ] Changes take effect immediately for subsequent `enabled?` calls (FR-8, with T07).

**Testing:** Request tests for index/create/edit/destroy; duplicate- and empty-name validation; member-count display; cascade verification.

### T11 — Build the user picker endpoint + autocomplete

**Requirements:** JSON search endpoint backed by `config.user_finder` returning
`{id, label}` (label via `user_display`), plus a minimal vanilla-JS
autocomplete wired to it. Defensive per PRD §11: finder errors or absence never
500.

**Acceptance criteria**
- [ ] `GET .../users.json?q=<query>` invokes `config.user_finder` and returns `[{id, label}, ...]`.
- [ ] Label honors `user_display` (default `to_s`).
- [ ] With `user_finder` unset, returns a clear safe error (e.g., 503 "user_finder not configured") — never a 500 stack.
- [ ] Finder raising ⇒ empty results + logged warning, never a 500.
- [ ] Autocomplete triggers the search and offers selectable results; no build step or external JS dependency.

**Technical considerations:** `user_finder` receives a query string and may
return any enumerable of objects responding to `id`, rendered via
`user_display`. Host apps are told to scope by their own tenant/auth (T16). Keep
the vanilla JS to one engine-shipped file.

**Testing:** Request tests for happy path (stub finder), custom `user_display` labels, missing-config error, raising-finder fallback; autocomplete smoke (automated if cheap, otherwise verified manually in the dummy app).

### T12 — Build the group membership admin screen

**Requirements:** Per-group membership management (FR-6/FR-7): list members
(labels via `user_display`), add users from the picker (T11), remove users;
stores polymorphic actor class + id (T03) and keeps evaluation and cache
consistent.

**Acceptance criteria**
- [ ] Membership screen lists members with `user_display` labels.
- [ ] Adding a picker result creates a `GroupMembership` (actor_type + actor_id), deduped.
- [ ] Removing deletes the membership.
- [ ] Add/remove take effect immediately: a group-targeted flag flips for the actor on the next `enabled?` call (FR-8 + T07).
- [ ] `groups_and_percentage` requires both membership and a passing bucket.
- [ ] Members whose actor records no longer resolve render defensively (label fallback, no crash).

**Testing:** Request tests for list/add/remove/duplicate; evaluation integration add→true and remove→false; missing-actor rendering.

### T13 — Add the audit trail (model, recording, admin view)

**Requirements:** `dwar_audits` recording who/what/when for flag, group, and
membership changes (create/update/destroy incl. targeting changes), written in
the same transaction as the change, plus a minimal admin list view
(newest-first). "Who" comes from optional `config.audit_actor` evaluated in the
admin request context (nil ⇒ null actor).

**Acceptance criteria**
- [ ] `dwar_audits` migration + model: auditable type/id, action, change summary, optional admin type/id, `created_at`.
- [ ] Every flag/group create/update/destroy and membership add/remove writes an audit row in the same transaction; flag targeting changes audit as flag updates.
- [ ] `who` recorded when `config.audit_actor` is configured; null otherwise.
- [ ] Audits index lists entries newest-first with a readable action/type/key summary.
- [ ] Recording failure is surfaced, not silently swallowed (decision documented).

**Technical considerations:** Record via `after_commit` on the models or an
abstraction invoked by admin controllers — pick the least invasive. Keep the
"who" contract aligned with the authorization hook so apps can reuse
`current_user`.

**Testing:** Unit tests for audit rows per mutation; request test for the audit list; configured `audit_actor` populates who; unconfigured ⇒ null.

### T14 — Build the install generator

**Requirements:** `rails generate dwar:install` (FR-1): copies the migrations
and generates an initializer with commented guidance for every T04 option plus
the recommended mount line.

**Acceptance criteria**
- [ ] Runnable as `bin/rails generate dwar:install` in the dummy app and documented for hosts.
- [ ] Copies all four migrations without duplicating on re-run.
- [ ] Generates `config/initializers/dwar.rb` with every option commented; defaults match T04.
- [ ] Output includes the recommended mount path.
- [ ] Covered by `Rails::Generators::TestCase`.

**Testing:** Generator tests (file creation, migration-copy idempotency); manual run in the dummy app.

### T15 — Set up the CI pipeline

**Requirements:** GitHub Actions workflow running tests and lint across the
pinned support matrix (Ruby 3.2/3.3/3.4 × Rails 7.1/7.2/8.0, via
Appraisal-style gemfiles or equivalent) — the automated enforcer of the
"passing suite" success criterion.

**Acceptance criteria**
- [ ] `.github/workflows/ci.yml` runs `bundle exec rake test` and the linter across the matrix.
- [ ] Per-Rails-version gemfiles exist and install cleanly.
- [ ] CI passes on the branch once pushed to GitHub.
- [ ] Dependency caching keeps runs reasonable.

**Testing:** `appraisal install` + `appraisal rake test` locally for each gemfile; green CI run after push.

### T16 — Write documentation (README, architecture, contributor guide)

**Requirements:** README (quickstart UF-1 + configuration reference FR-11),
architecture overview (namespace, models, evaluation flow, caching, security),
and a contributor/development guide. Quickstart steps must work when followed
against the dummy app.

**Acceptance criteria**
- [ ] README quickstart: add gem → run installer → migrate → mount → configure `user_finder` → call `Dwar.enabled?(:key, current_user)`; verified end-to-end (cross-checked against the published gem in T17).
- [ ] Configuration reference documents every T04 option with meaning, type, default, and example.
- [ ] Architecture doc covers namespacing/isolation (FR-9), schema, evaluation resolution (FR-3), the bucketing stability contract (FR-4/T05), caching + invalidation (T07), fail-closed authorization (FR-10), audit (T13), and the admin JS footprint.
- [ ] Contributor guide: dev setup, test/lint/CI commands, and the branch/PR workflow (one task → one branch → one PR).
- [ ] Docs match the implemented code.

**Testing:** Walk the quickstart against the dummy app; doc-accuracy review as part of the PR.

### T17 — Package and publish the gem to RubyGems

**Requirements:** Build a clean `.gem`, publish to RubyGems under `dwar`, and
smoke-test integration from a fresh Rails app using the published gem
(quickstart UF-1). Requires human authorization and RubyGems credentials.

**Acceptance criteria**
- [ ] `gem build dwar.gemspec` produces a clean package (complete files, no dev artifacts, version from T01).
- [ ] Published to RubyGems with correct metadata (name, MIT, homepage/source links, description).
- [ ] Fresh Rails app: add published gem → installer → migrate → mount → configure `user_finder` → `Dwar.enabled?` resolves correctly.
- [ ] Docs updated if the smoke test surfaces anything.

**Technical considerations:** Requires human-provided RubyGems credentials and
explicit go-ahead; scheduled but awaits authorization before execution.
Optionally tag the release (e.g., `v0.1.0`) with a matching GitHub release.

**Testing:** Local gem build/install smoke; fresh-app quickstart; rubygems.org page check post-publish.

---

## 6. PRD coverage

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
| Success criteria: suite + dummy app + docs | throughout; T02, T16 |
| Success criteria: published to RubyGems | T17 |

Every Must Have and Should Have is covered by at least one task. The three
explicit Nice-to-Haves (YAML import/export, per-environment overrides, admin UI
polish) are intentionally **not** decomposed; they can be added later as
follow-up tasks without changing this plan.

---

## 7. Testing and documentation strategy

**Testing strategy**

- **Framework:** Minitest (Rails default) with fixtures in the dummy app
  (`test/dummy`), run from the gem root via `bundle exec rake test`.
- **Layers:**
  - *Unit* — pure logic first: bucketing (T05) determinism/range/distribution,
    configuration defaults and isolation (T04), model validations and
    associations (T03), evaluation rules (T06), cache behavior (T07).
  - *Request/integration* — against the dummy app: admin authorization
    (T08), CRUD screens (T09, T10), picker endpoint (T11), membership (T12),
    audit view (T13).
  - *Generator* — `Rails::Generators::TestCase` for the installer (T14).
  - *Migration* — up/down verification in the dummy app (T03, T13).
- **End-to-end expectations:** create→evaluate (T09), membership add→true /
  remove→false (T12), write→immediate effect with cache on (T07, FR-8), and the
  full quickstart against a fresh app from the published gem (T17).
- **Matrix enforcement:** CI (T15) runs the suite and linter across Ruby
  3.2/3.3/3.4 × Rails 7.1/7.2/8.0.
- **Non-flaky rule:** statistical/distribution assertions use broad bounds;
  no exact-value assertions on distribution.
- **Per-task requirement:** every task adds or updates tests for the behavior it
  introduces; each PR must show the focused tests plus the suite result.

**Documentation strategy**

- **In-repo, layered:** README (quickstart + configuration reference),
  architecture overview, and contributor guide, all delivered in T16 and
  kept in sync thereafter.
- **In-code:** every public API (`Dwar.enabled?`, `Dwar.configure`, the
  bucketing contract, the `user_finder`/`authorization`/`audit_actor`
  callables) documented at its definition; the bucketing tuple documented as
  a stability promise.
- **Generator-generated:** the installer emits a commented initializer so host
  apps carry accurate inline documentation of every option (T14).
- **Traceability:** each task maps to one branch and one PR (global workflow
  conventions); PR descriptions link to the Notion card, and this plan records
  the approved scope.

---

## 8. Notion board and cards

**Board:** Dwar — `https://app.notion.com/p/1c2188dd8aa846378d4db1d0ef8836e7`
(data source `collection://67b50cda-89f5-45ae-91b6-e7d15593e632`)

The board is a §8-standard Kanban data source: `Name` (title), `Status`
(Not started / In development / Testing / Reviewing / Done), `Description`,
`Acceptance Criteria`, `Dependencies`, `Technical Considerations`,
`Testing Requirements`, `GitHub PR` (URL). Views: Kanban board (grouped by
Status), Detailed board (grouped by Status), Table view, Status overview
(donut by Status).

**Known deviations from the §8 template (informational):**
- `Status` is implemented as a **select** property rather than Notion's
  `status` type. The Notion API rejects setting workflow states/groups on a
  `status` property (`validation_error`), so the five workflow states are
  select options. State names and ordering match §8; this matches the existing
  `Aafnai Coffee` board precedent in this workspace.
- The §8 `Task` page **template** cannot be created through the API and must
  be added manually in the Notion UI if desired. Cards were created directly
  against the data source, so this does not affect the tickets.

| ID | Card | Notion |
|----|------|--------|
| T01 | Set up gem scaffolding and pin the support matrix | https://app.notion.com/p/3e05bbd6ec0d81f78920fa486da09f91 |
| T02 | Bootstrap the mountable engine with a dummy app | https://app.notion.com/p/3e05bbd6ec0d810294d6e78f3ca0df8d |
| T03 | Build the data model (migrations + models) | https://app.notion.com/p/3e05bbd6ec0d8174a0b4c88a53ae265b |
| T04 | Implement the configuration surface | https://app.notion.com/p/3e05bbd6ec0d81b6b90fd707644d6fb6 |
| T05 | Implement deterministic percentage bucketing | https://app.notion.com/p/3e05bbd6ec0d819fa43ef86509e988b6 |
| T06 | Implement the evaluation API (`Dwar.enabled?`) | https://app.notion.com/p/3e05bbd6ec0d8164a51dc559b0e49402 |
| T07 | Implement in-process caching with write invalidation | https://app.notion.com/p/3e05bbd6ec0d8174806fe248fdc68f9d |
| T08 | Build the admin UI shell (routes, base controller, fail-closed authorization) | https://app.notion.com/p/3e05bbd6ec0d81b69a98f03fd34dd802 |
| T09 | Build the flags admin screens (CRUD + search/filter) | https://app.notion.com/p/3e05bbd6ec0d81a48581f85e5b7f7098 |
| T10 | Build the groups admin screens (CRUD) | https://app.notion.com/p/3e05bbd6ec0d81a4ba55f38465172d0d |
| T11 | Build the user picker endpoint + autocomplete | https://app.notion.com/p/3e05bbd6ec0d81d497c3ec90055604cd |
| T12 | Build the group membership admin screen | https://app.notion.com/p/3e05bbd6ec0d818d95b7d662c171c9ab |
| T13 | Add the audit trail (model, recording, admin view) | https://app.notion.com/p/3e05bbd6ec0d81638d14f5e477d6d1a4 |
| T14 | Build the install generator | https://app.notion.com/p/3e05bbd6ec0d81d089a8c79693b4b65b |
| T15 | Set up the CI pipeline | https://app.notion.com/p/3e05bbd6ec0d8163a4abc0891203d546 |
| T16 | Write documentation (README, architecture, contributor guide) | https://app.notion.com/p/3e05bbd6ec0d8130a043d9a0e10c0238 |
| T17 | Package and publish the gem to RubyGems | https://app.notion.com/p/3e05bbd6ec0d81ab834ee465d10c277e |

All 17 cards are created with `Status = Not started` and an empty `GitHub PR`
(verified 2026-09-19).

---

## 9. Risks and open items

| Risk / item | Note |
|---|---|
| Bucketing contract stability | The hash tuple is a public stability promise; changing it post-release re-buckets every rollout. Documented in T05 and guarded by tests. |
| Cache correctness | A stale evaluation would silently mis-serve flags. Mitigated by generation-versioned keys, `after_commit` invalidation, and cached/uncached equivalence tests (T07). |
| Fail-closed default | Without an authorization hook the admin is unusable by design. Documented prominently in T14/T16 so hosts are not surprised. |
| Dummy-app maintenance | `test/dummy` is committed and must be kept in sync as migrations, routes, and config land (T02 onward). |
| Matrix drift | Rails 8.0 / Ruby 3.4 behavior differences are surfaced by the T15 CI matrix rather than discovered at publish time. |
| T17 release authorization | Publishing requires human-provided RubyGems credentials and an explicit go-ahead; it is scheduled, not automatic. |
| Nice-to-haves deferred | YAML import/export, per-environment overrides, and UI polish are out of scope; they can be added as follow-up tasks without replanning. |

---

*Approved by the human manager on 2026-09-19. Notion remains the live source of
task workflow state; this document remains the approved scope and decision
record.*
