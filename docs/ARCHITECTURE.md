# dwar — Architecture

Authoritative technical overview of the `dwar` engine. The README covers
quickstart and configuration; this document covers how the pieces fit together
and the contracts contributors must not break.

## Namespace isolation (FR-9)

- The engine is `Dwar::Engine < Rails::Engine` (`lib/dwar/engine.rb`) with
  `isolate_namespace Dwar`. All models, controllers, helpers, and view paths
  live under `Dwar::` (`Dwar::Flag`, `Dwar::Admin::FlagsController`, …).
- The engine never monkey-patches host classes. `Dwar::ApplicationRecord` is
  `abstract_class = true` only — it deliberately does **not** claim the single
  `primary_abstract_class` slot (Rails 8.1 raises if more than one exists per
  application); the host app's own `ApplicationRecord` owns it.
- Database tables use the `dwar_` prefix (`dwar_flags`, `dwar_groups`,
  `dwar_flag_groups`, `dwar_group_memberships`, `dwar_audits`).
- The engine never mounts itself. Mounting is host-side
  (`mount Dwar::Engine => "/dwar"` in the host's `config/routes.rb`);
  `config.admin_path` documents the expected path. Engine URL helpers adapt to
  the mount path automatically.
- The actor (end user) is owned by the host app: memberships store a
  polymorphic `actor_type`/`actor_id` reference with **no foreign key** to host
  tables, and actors only need to expose a stable `id`.
- The dummy app (`test/dummy`) is the engine's test harness and example host,
  versioned alongside the engine. It is **not** packaged into the built gem
  (the gemspec `files` whitelist covers `lib`, `app`, `config`, `db`,
  `LICENSE.txt` only). User-facing picker demo code lives in the dummy app,
  not the gem.

## Schema (4 + 1 tables)

Migrations live in `db/migrate` and are shipped to hosts by the install
generator (`rails generate dwar:install`, T14), which copies them with fresh
timestamps and skips already-copied ones.

| Table | Key columns / constraints |
|---|---|
| `dwar_flags` | `key` (unique, format `\A[a-z0-9_/.-]+\z`), `description`, `state` (string enum, default `"disabled"`), `percentage` (integer, default `0`) |
| `dwar_groups` | `name` (unique), `description` (optional) |
| `dwar_flag_groups` | join flag ↔ targeted groups; `flag_id`/`group_id` FKs with `on_delete: :cascade` (explicit `to_table:` — plain `foreign_key: true` would infer unprefixed tables); unique compound `(flag_id, group_id)` |
| `dwar_group_memberships` | polymorphic actor: `group_id` FK (cascade) + `actor_type`/`actor_id` with **no** actor FK; unique compound `(group_id, actor_type, actor_id)`. `actor_id` is a **string** column (T12 migration) so integer, UUID, and other host key shapes fit; lookups bind `actor.id.to_s` explicitly so integer ids keep matching stored `"42"` on every adapter. Matching is verbatim (`"42" != "042"`, no stripping/padding) |
| `dwar_audits` | `auditable_type`/`auditable_id` (strings — integer, UUID, and other host key shapes), `action` (`create`/`update`/`destroy`), `change_summary` (serialized JSON), optional `actor_type`/`actor_id` (strings, NULL when unconfigured), timestamps. **No foreign keys by design:** audited records are routinely destroyed (their rows must survive) and membership actors live outside the engine's tables. Indexes on `(auditable_type, auditable_id)`, `created_at`, `(actor_type, actor_id)` |

Flag states (`Dwar::Flag` enum, string-backed): `disabled`, `enabled`,
`percentage`, `groups`, `groups_and_percentage`. `percentage` is validated as
an integer `0..100` only for the two percentage-style states; every other
state ignores it at evaluation time and the flags controller resets it to `0`
on write so a stale value can never persist silently.

## Flag evaluation (FR-3, T06)

Public API: `Dwar.enabled?(flag_key, actor = nil)` → boolean, never raises
(`lib/dwar/evaluator.rb`, re-exported from `lib/dwar.rb`). Uncached core:

1. Unknown flag key → `false`.
2. `disabled` → `false`.
3. `enabled` → `true`.
4. `percentage` → `false` unless an actor is supplied; then `true` iff
   `Bucketing.bucket(key, actor.class, actor.id) < percentage`.
5. `groups` → `false` unless an actor is supplied; then `true` iff a
   `GroupMembership` row exists for the actor (`actor_type` + stringified
   `actor_id`) in any targeted group. No bucket check.
6. `groups_and_percentage` → membership **and** bucket must both pass.

Defensive rules preserving the never-raise contract: actors with nil/blank
ids, or objects without an `id`, yield `false` instead of raising (bucketing
is never called with invalid args; membership lookup binds `to_s`); the cache
key normalization mirrors this. Uncached evaluation is single-digit-ms DB
lookups (flag row, then at most one membership `EXISTS` query).

## Deterministic bucketing (FR-4, T05)

`Dwar::Bucketing.bucket(flag_key, actor_class, actor_id)` → integer `0..99`
(`lib/dwar/bucketing.rb`). This is a **public stability promise**: the scheme
must not change post-release or every rollout re-buckets.

- **Scheme (versioned):** `tuple = "dwar-v1|<flag_key>|<actor_class>|<actor_id>"`;
  `bucket = Digest::SHA256.digest(tuple)[0, 4].unpack1("N") % 100`.
  `SCHEME_PREFIX` (`"dwar-v1"`) marks the version — any future tuple/digest
  change MUST bump it and regenerate the pinned values in
  `test/bucketing_test.rb`. SHA-256 provides distribution stability, not
  cryptography; the mod-100 bias from `2**32 % 100` is ~2.3e-8 relative.
- The `"|"` separator is collision-safe because flag keys are validated
  against `Dwar::Flag::KEY_FORMAT` (`/\A[a-z0-9_\/.-]+\z/`), which forbids `"|"`.
- **Normalization:** flag keys via `to_s` (`:rollout` ≡ `"rollout"`); actor
  classes via `to_s` (`User` ≡ `"User"`); actor ids via `to_s` (`42` ≡ `"42"`).
  `nil`/empty inputs are rejected with `ArgumentError`. Actor ids match
  verbatim against persisted ids — no stripping, no zero-padding.
- The evaluator owns the boundary math (`bucket < percentage`); bucketing owns
  only the stable integer.

## Evaluation caching (T07)

In-process, read-through cache (`lib/dwar/cache.rb`), ON by default via
`Dwar.config.cache`; `false` re-evaluates every call.

- **Key shape:** `[flag key, actor type, actor id, global generation, flag
  version]`. Actor normalization is defensive (`nil` → `["", ""]`) so the
  never-raise contract holds with caching on.
- **Invalidation — coarse and correct:** every committed write bumps a global
  generation counter *and* the touched flags' versions while evicting all
  stored entries under one mutex. Per-flag versions exist for future selective
  invalidation; today any write invalidates everything process-wide, so the
  next `enabled?` call recomputes. Multi-process caching is out of scope by
  design (each process holds its own copy).
- **Hooks:** `after_commit` on `Flag` (both the current and previous key, so
  renames invalidate), `FlagGroup` (resolves flag keys from ids), `Group` and
  `GroupMembership` (resolve targeting flag keys from group ids) — all via
  `Dwar::Cache.bump_flags*`. `after_commit` only, so rolled-back transactions
  invalidate nothing. Key resolution is best-effort and never raises, so hooks
  cannot break the write that triggered them; callers that cannot resolve keys
  (e.g. after a cascade destroy) still bump the generation.
- **Caveat:** writes that bypass callbacks (`update_column`, `update_all`,
  `delete_all`, raw SQL) leave stale entries until the next invalidating
  write. Audit rows deliberately have no cache hooks.
- **Concurrency:** one mutex guards all state; the lock is never held while
  the fetch block hits the database, and a computation that races with an
  invalidation is discarded instead of stored. The hit/miss counters,
  `generation`, `clear`, and `reset!` are internal test instrumentation, not
  public API (`reset!` replaces the lock — call only with no concurrent
  evaluation).
- **Semantics guarantee:** cached results always equal uncached results;
  the cache never changes what a flag resolves to.

## Fail-closed authorization (FR-10, T08)

All admin controllers inherit `Dwar::Admin::BaseController`, whose
`before_action :authorize_admin!` evaluates `config.authorization` with the
controller as context:

- No hook (`nil`) or non-callable → `403` with a clear message.
- Hook returns falsy → `403`.
- Hook returns truthy → proceed.
- Hook raises → propagates as a 500 (fail-loud — never fail-open).

Default-denied is deliberate: the admin area is inert until the host app
explicitly configures access. Hosts scope tenancy/auth inside their own
`user_finder`/hook; the engine does not second-guess them.

## Audit trail (T13)

Explicit, same-transaction recording (`lib/dwar/auditing.rb`), invoked by the
admin controllers — **not** model callbacks:

- Each mutating request resolves the actor once via `Auditing.resolve_actor`
  (same controller-context contract as the authorization hook; `nil` hook or
  falsy return → `[nil, nil]` null actor; a raising hook propagates so the
  write never commits unattributed-by-accident), then wraps the model write
  **and** the `Auditing.record!` call in one `Dwar::ApplicationRecord`
  transaction. An audit validation failure rolls the write back and surfaces —
  never silently swallowed. Direct model writes (console, seeds) leave no
  trail, by design.
- Flag create/destroy store a point-in-time snapshot (key, description, state,
  percentage, group names); flag updates store a curated diff of changed
  attributes plus an added/removed group-name diff. Group create/update/destroy
  analogously (name, description). Membership add/remove stores group identity
  (from the controller's loaded group — safe even after the row is gone) plus
  the polymorphic actor reference. Join-table churn is not audited directly:
  targeting is captured as a group-name diff on the flag. Summaries use
  denormalized labels (group names, not full records) to bound size and PII.
- `Dwar::Audit` validates `auditable_type`/`auditable_id`/`action` presence
  and `action ∈ {create, update, destroy}`; `newest_first` orders by
  `(created_at, id)` so same-second rows keep write order. The admin list
  (`AuditsController#index`) is read-only, newest-first, capped at 200 rows
  (pagination deferred), with best-effort record labels batched per auditable
  type (destroyed records render as `"Type #id (removed)"`, never a crash) and
  actor labels (`"User #1"`, em dash for null actors).

## Admin JS footprint

Exactly one shipped JS file: `app/assets/javascripts/dwar/user_picker.js`
(vanilla JS, no framework, no build step). `DwarUserPicker.init(input, {url,
hiddenField, list?, debounceMs?})` debounces keystrokes (default 200ms, `0`
disables), fetches `url?q=…` (appending with `?`/`&` as needed), renders a
selectable list (click/Enter selects into the visible label + hidden id;
arrows/Escape navigate/dismiss), guards responses with a monotonic request
token so a slow earlier response never overwrites newer results, and never
throws — empty queries and fetch/parse failures render the empty state. The
engine ships no asset-pipeline config; the dummy app's dev-only demo harness
(`UserPickerDemoController`, routes `/user_picker_demo`) serves this file
directly for manual verification. Picker results are capped at 50 items
(`UsersController::PICKER_RESULT_LIMIT`); hosts must scope/cap inside
`user_finder` itself. Picker logs carry the error class only, never the query
or record data (PII).
