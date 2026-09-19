# Product Requirements Document

**Project:** feature-flags-engine (workspace folder)
**Gem name:** `dwar` · namespace `Dwar`
**Status:** ✅ Approved by human manager — final (2026-09-19)
**Date:** 2026-09-19

---

## 1. Product Summary

**dwar** is a reusable, open-source Rails engine (mountable gem) that gives any
Rails application managed feature flags: full enable/disable, deterministic
percentage rollouts, and group-based user targeting — administered through a
Rails-Admin-style web UI and evaluated through a simple developer API.

This is a deliberate learning/portfolio build. The goal is a polished,
idiomatic, well-tested engine that recreates the category's fundamentals
excellently rather than introducing novel or exotic features.

## 2. Problem Statement

Deploying every feature all-at-once to every user is risky. Teams need to
control **when** and **to whom** features are visible:

- turn a bad feature off instantly (kill switch),
- roll features out gradually to a percentage of users,
- show features only to designated groups (beta testers, specific regions,
  premium users).

Without a feature-flag system, teams either ship all-or-nothing or hand-roll
fragile flag checks scattered across application code, usually without a UI,
consistency, or tests.

This product removes that risk for any Rails app by packaging a complete,
reusable feature-flag system — data model, evaluation logic, and admin UI — as
a mountable engine.

## 3. Target Users

| Type | Who | What they do |
|---|---|---|
| **Primary** | Rails developers | Install and mount the engine, configure the user finder, call the evaluation API, manage flags pragmatically. |
| **Secondary** | Application admins / operators | Use the mounted web UI to create flags, run percentage rollouts, manage groups, and control user access — without touching code or deploys. |

The host app's own end users are not users of this product; they are the
subjects that flags target.

## 4. Product Goal

Provide a well-engineered, documented, mountable Rails engine that lets any
Rails application manage feature availability through full enable/disable,
deterministic percentage rollouts, and group-based user targeting — managed via
an admin UI and queried through a simple, explicit developer API. Delivered as
an open-source gem of portfolio quality.

## 5. Success Criteria

- A developer can integrate the engine into an existing Rails app in a few
  steps (add gem, migrate, mount, configure the user finder) and immediately
  evaluate flags against the app's own user model.
- An admin can change flag availability (enable/disable/percentage/group
  targeting) and the change takes effect **immediately** — no deploy, no
  restart.
- Percentage rollouts are **deterministic per user**: the same user always
  receives the same result for a given flag (no flickering between requests).
- The admin can create groups, manage membership with resolver-backed search,
  and target flags at groups with an optional additional percentage
  restriction.
- The gem ships with a passing automated test suite, a dummy application for
  development and manual verification, and documentation covering quickstart,
  configuration, architecture, and the contributor workflow.
- The engine is packaged as a gem and **published to RubyGems** as part of this
  effort.

## 6. MVP Scope

### Must Have

1. **Mountable Rails engine** in an isolated `Dwar` namespace, with an
   install generator (required migrations, mount instruction, initializer).
2. **Data model**:
   - `Flag` — unique key, state, percentage where applicable.
   - `Group` — named groups with optional description.
   - Group membership — polymorphic actor references (actor class + id).
3. **Flag states**: disabled, fully enabled, percentage rollout (0–100),
   group-targeted, and group-targeted + percentage.
4. **Deterministic percentage bucketing** per user, stable across requests.
5. **Developer API**: `Dwar.enabled?(:key)` and
   `Dwar.enabled?(:key, user)` returning booleans. Unknown flags
   resolve to `false` (fail closed).
6. **Admin UI** (Rails-Admin-style, server-rendered):
   - CRUD flags; set state and percentage.
   - CRUD groups.
   - Manage group membership — add/remove users.
   - **User picker** with searchable autocomplete backed by a configurable
     `user_finder`.
7. **Configuration surface**: `user_finder` (required for the picker),
   `user_display` (defaults to `to_s`), admin mount path, authorization hook.
8. **Documentation**: README (quickstart + config reference), architecture
   overview, contributor/development guide.
9. **Dummy app** inside the gem for development, manual testing, and
   documentation.
10. **Automated tests**: flag/group/membership logic, deterministic rollout
    behavior (stability, boundaries, 100% edge), admin controller smoke tests.

### Should Have

- Evaluation **caching** with invalidation on relevant writes (keeps
  per-request evaluation cheap while preserving immediate effect).
- **Authorization hook** for the admin UI (host app controls who may access
  it).
- **Audit trail** of flag/group changes (who, what, when).
- Flag list search/filtering in the admin UI.

### Nice to Have

- YAML import/export of flags (environment seeding).
- Per-environment overrides.
- Admin UI polish (icons, breadcrumbs, theming).

## 7. Out of Scope

- Attribute-based rule targeting (e.g., `region == "US"`, `plan == "premium"`)
  — deferred to a later version; groups are manually managed in v1.
- Distributed / multi-service flag infrastructure (Redis pub/sub, central
  flag service, webhooks, real-time client push).
- A/B experiment analytics or metrics dashboards.
- Multi-tenancy.

## 8. Functional Requirements

**FR-1 — Integration.**
`Dwar` is a mountable Rails engine (gem name `dwar`). An install generator
copies the required migrations and an initializer; mounting exposes the admin
UI at a configurable path (default `/dwar`).

**FR-2 — Flag model.**
Flags are identified by a unique key (e.g., `new_checkout`). Each flag has a
state in {disabled, enabled, percentage, groups, groups + percentage} and a
percentage (0–100) where applicable.

**FR-3 — Evaluation resolution.**
`Dwar.enabled?(:key, actor = nil)` returns a boolean per resolution
order:

1. Flag disabled → `false`.
2. Flag fully enabled → `true`.
3. Percentage-only → `true` iff an actor is supplied **and**
   `bucket(actor) < percentage`; with no actor → `false`.
4. Group-targeted → `true` iff the actor belongs to a targeted group and, when
   a percentage is set, `bucket(actor) < percentage`.
5. Unknown flag key → `false` (never raises).

**FR-4 — Deterministic bucketing.**
The bucket is derived from a stable hash of (flag key, actor class, actor id).
The same actor + flag always resolves identically across requests; changing the
percentage only shifts the cutoff. At 100%, all actors pass.

**FR-5 — Groups.**
Groups have a unique name and optional description. Membership is a set of
actor references (class + id) managed through the admin UI. Flags may target
one or more groups.

**FR-6 — Admin UI.**
Server-rendered admin screens:

- Flags index (with state and current targeting summary), create/edit/delete,
  set state and percentage, choose targeted groups.
- Groups index, create/edit/delete.
- Group membership screen: add/remove users.

**FR-7 — User picker.**
The host app configures `config.user_finder = ->(query) { ... }`. The admin UI
queries it through a server endpoint to search and select users. The engine
stores class + id and renders members using `user_display` (defaults to
`to_s`).

**FR-8 — Immediate effect.**
Flag, group, and membership changes are visible to subsequent evaluations
without an app restart or deploy. If caching is implemented, writes invalidate
the relevant cache entries.

**FR-9 — Namespace isolation.**
All engine internals live under `Dwar::`. No monkey-patching of the
host app's models/controllers. Database tables use a prefixed naming scheme
(e.g., `dwar_flags`, `dwar_groups`).

**FR-10 — Security.**
Admin routes are protected by an authorization hook the host app configures.
Default behavior is **fail closed**: the admin area is inert/unreachable for
authorized actions until the host app explicitly configures access.

**FR-11 — Configuration.**
A single initializer exposes: `user_finder`, `user_display`, admin mount path,
authorization hook, and cache toggle (when caching lands).

## 9. Core User Flows

**UF-1 — Developer integration (quickstart).**
Add gem → run install generator → migrate → mount engine → configure
`user_finder` → call `Dwar.enabled?(:key, current_user)`.

**UF-2 — Admin creates a flag before shipping code.**
Open flags → New → key + description → create (default: disabled). Developers
ship code behind the disabled flag with zero exposure.

**UF-3 — Gradual percentage rollout.**
Admin edits flag → percentage 10% → watch/verify → 25% → 50% → 100% → fully
enabled. Rollback at any step by lowering the percentage or disabling.

**UF-4 — Group-targeted rollout.**
Admin creates "Beta Testers" group → searches and adds users via the picker →
targets the flag at the group → optionally restricts further with a percentage.

**UF-5 — Kill switch.**
Admin disables a misbehaving flag; the feature is off immediately.

**UF-6 — Flag sunset.**
Once a flag is fully enabled and stable, developers remove evaluation calls and
delete the flag.

## 10. Constraints

- Rails engine packaging conventions (gemspec, isolated namespace, mountable,
  dummy app required by gem development conventions).
- Modern Rails & Ruby support. Proposed minimums: Rails ~> 7.1, Ruby >= 3.2 —
  exact matrix pinned during technical planning.
- All state persisted to the host application's database via documented
  migrations. No external services or paid dependencies in the MVP.
- Server-rendered admin UI with minimal JavaScript (autocomplete only). No SPA
  build step.
- Open-source licensing (MIT); must not require secrets, cloud accounts, or
  external setup.
- Actors must expose a stable `id` used for deterministic bucketing and
  membership storage.
- Caching (Should Have, delivered in this effort) is **in-process with
  write-invalidation** on flag/group changes — confirmed decision.

## 11. Risks

- **Scope creep** — attribute-rule segments and experiment analytics are
  tempting; explicitly out of scope for v1.
- **Evaluation performance** — uncached `enabled?` calls hit the DB on each
  request; addressed by caching (Should Have) and verified in the dummy app.
- **Admin exposure** — mitigated by fail-closed authorization hook and
  conservative defaults.
- **Resolver contract brittleness** — host user models vary wildly; mitigated
  by a small, documented interface, defensive handling, and `to_s` display
  fallback.
- **Bucketing correctness** — modular hashing biases and 100% edge cases
  covered by dedicated tests.
- **Rails version churn** — support matrix pinned during technical planning.

## 12. Open Questions

- Exact Rails/Ruby **support matrix** (technical planning).
- **Authorization integration style** for the admin UI: simple proc/config
  hook vs. adapter (e.g., Pundit-style).

## 13. Assumptions

- This is a **learning/portfolio build**: polish fundamentals, don't chase
  novel features.
- **Manual group membership** is sufficient for v1; attribute-based rules are
  deferred.
- Percentage evaluation requires an **actor**; without one, a percentage flag
  resolves to `false`.
- Deterministic per-actor bucketing is the desired rollout semantics
  (confirmed).
- All state lives in the host DB; no external services.
- Admin UI is server-rendered with minimal JS.
- MIT license.
- Unknown flag keys resolve `false` (fail closed).
- Admin UI defaults to denied access until the host app configures
  authorization (fail closed).