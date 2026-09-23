# dwar

Managed feature flags for Rails: full enable/disable, deterministic percentage
rollouts, and group-based user targeting — administered through a
server-rendered web UI and queried through a simple developer API
(`Dwar.enabled?`).

`dwar` is a mountable Rails engine (isolated `Dwar` namespace) packaged as an
open-source MIT gem. All state lives in the host application's database via
documented migrations. No external services, no JS build step, no secrets.

- **Support matrix:** Rails `>= 7.1` (CI tests 7.1, 7.2, 8.0) · Ruby `>= 3.2`
  (CI tests 3.2, 3.3, 3.4)
- **Docs:** [Architecture](docs/ARCHITECTURE.md) · [Contributing](CONTRIBUTING.md)

## Quickstart (UF-1)

These steps work verbatim against the bundled dummy app in `test/dummy`
(which mounts the engine at `/dwar` and has a `User` model with a `name`
column). The published-gem cross-check against a fresh app is covered in T17.

```ruby
# Gemfile
gem "dwar"
```

```sh
bundle install
bin/rails generate dwar:install
bin/rails db:migrate
```

The generator copies the engine migrations into `db/migrate` (skipping ones
already present, so re-runs never duplicate) and generates
`config/initializers/dwar.rb` with every option commented (skipped when
already present, so re-runs never clobber host edits). It then prints the
recommended next steps, including the mount line.

Mount the engine in `config/routes.rb` (host-side — the engine never mounts
itself):

```ruby
mount Dwar::Engine => "/dwar"
```

`config.admin_path` (default `"/dwar"`) documents the *expected* path; the
mount line above is what actually exposes the admin UI there.

Configure the user picker in `config/initializers/dwar.rb`:

```ruby
Dwar.configure do |config|
  # Required only when the user picker endpoint is used
  # (sanitize LIKE wildcards, then scope and cap inside the finder itself):
  config.user_finder = ->(query) {
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    User.where("name LIKE ?", pattern).order(:name).limit(50)
  }
  config.user_display = :name

  # Fail-closed admin gate — without this, every admin request is denied:
  config.authorization = ->(controller) { controller.current_user.admin? }
end
```

Evaluate flags in application code:

```ruby
Dwar.enabled?(:new_checkout)                 # no actor — true only when fully enabled
Dwar.enabled?(:new_checkout, current_user)   # percentage / group checks need an actor
```

Then open the admin UI at the mount path (e.g. `http://localhost:3000/dwar`):
create a flag (default state: disabled, evaluates `false` immediately), roll
it out via percentage or group targeting, and disable it again as a kill
switch. Changes take effect on the next `enabled?` call — no deploy, no
restart.

## Configuration reference (FR-11)

A single initializer exposes every option. All options are optional at boot;
`user_finder` is required only when the picker endpoint is exercised. The
generated `config/initializers/dwar.rb` shows the same defaults as comments.

| Option | Type | Default | Meaning / example |
|---|---|---|---|
| `user_finder` | callable `->(query) { users }` | `nil` | How the user picker (`GET .../admin/users.json?q=…`) looks up records. Receives a query `String`, returns any enumerable of records responding to `id`. Hosts should scope and cap inside the finder itself (e.g. a `LIMIT` query) — the endpoint only bounds the JSON body (50 items). Unset → the endpoint returns `503 "user_finder not configured"`. A raising finder returns `[]` plus a logged warning — never a 500 for StandardError failures (fatal errors still propagate by design). Example: `config.user_finder = ->(query) { User.search(query) }` |
| `user_display` | method name (`Symbol`/`String`) or callable | `:to_s` | How picker labels and membership lists render a record. A `Symbol`/`String` is sent to the record (`record.public_send(display)`); a callable is called with the record (`display.call(record)`). `nil` falls back to `:to_s`. An unknown method name falls back to `to_s` with a logged warning; any other per-record failure skips just that record. Example: `config.user_display = :display_name` |
| `admin_path` | `String` | `"/dwar"` | The path the admin UI is expected at. Informational — the host still mounts the engine explicitly (`mount Dwar::Engine => "/dwar"`). Example: `config.admin_path = "/admin/dwar"` (and mount there) |
| `authorization` | callable `->(controller) { bool }` | `nil` | Gatekeeper for the whole admin UI, evaluated with the admin controller as context (so it can call host helpers like `current_user`). `nil`/non-callable → every request denied (`403` fail-closed). Falsy result → `403`. A raising hook propagates as a 500 (fail-loud, never fail-open). Example: `config.authorization = ->(controller) { controller.current_user.admin? }` |
| `cache` | Boolean | `true` | Whether `Dwar.enabled?` results are served from the in-process evaluation cache. `false` re-evaluates on every call. See [Architecture](docs/ARCHITECTURE.md#evaluation-caching-t07) |
| `audit_actor` | optional callable `->(controller) { identity }` | `nil` | How admin writes are attributed in the audit trail, evaluated in the admin controller context (same contract as `authorization`, so apps can reuse `current_user`). `nil`/non-callable or a falsy return → null actor (`actor_type`/`actor_id` NULL). A raising hook propagates — the write never commits unattributed-by-accident. Example: `config.audit_actor = ->(controller) { controller.current_user }` |

`Dwar.configure` builds a fresh instance per call, so configuration never leaks
between apps or between configure blocks. Reading `Dwar.config` before any
`configure` call returns a frozen default instance; `Dwar.reset_config` drops
the memoized config (internal test/dev support, not public API).

## Evaluation summary (FR-3)

`Dwar.enabled?(flag_key, actor = nil)` returns a boolean and never raises.
Resolution order:

1. Unknown flag key → `false`.
2. `disabled` → `false`.
3. `enabled` → `true` (actor not needed).
4. `percentage` → `true` iff an actor with a stable non-blank `id` is supplied
   **and** `bucket(actor) < percentage`; no actor → `false`.
5. `groups` → `true` iff the actor belongs to a targeted group; no bucket check.
6. `groups_and_percentage` → `true` iff the actor belongs to a targeted group
   **and** `bucket(actor) < percentage`.

Percentage math is deterministic per actor: the same actor + flag always lands
in the same bucket (`0..99`), so raising the percentage only shifts the cutoff
— no flickering. At `100`, every actor with a stable id passes (max bucket is
99); at `0`, everyone fails. The `percentage` column is only meaningful for the
`percentage` and `groups_and_percentage` states; other states ignore it at
evaluation time, and the admin flags controller resets it to `0` on write so
a stale value submitted via the UI can never persist silently (direct model
writes bypass this normalization — there is no model callback).

Details: [Architecture](docs/ARCHITECTURE.md#flag-evaluation-fr-3-t06) and
[bucketing contract](docs/ARCHITECTURE.md#deterministic-bucketing-fr-4-t05).

## Admin UI

Server-rendered, no build step. Engine root (`/`) routes to the flags index.

- **Flags** (`/admin/flags`): CRUD + search by key/description substring; per-flag
  state and targeting summary (percentage value, targeted group names); create
  defaults to `disabled`; destroy removes the flag and its targeting rows.
- **Groups** (`/admin/groups`): CRUD with unique-name validation; index shows
  member counts; destroy cleans up memberships and flag-targeting rows.
- **Memberships** (`/admin/groups/:id/memberships`): list members, add via the
  user picker, remove; duplicate adds rejected; members whose host records no
  longer resolve render with a label fallback instead of crashing.
- **User picker** (`/admin/users.json?q=…`): JSON `[{id, label}, …]` from
  `user_finder`, labels via `user_display`; vanilla-JS autocomplete in a single
  shipped file (`app/assets/javascripts/dwar/user_picker.js`) — mousedown/Enter
  selects into the visible label + hidden id.
- **Audits** (`/admin/audits`): newest-first list (capped at 200 rows) of who
  changed what, when.

Every admin route inherits the fail-closed authorization gate — with no
`authorization` hook configured, the whole area returns `403`.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, `bundle exec rake test`,
`bundle exec standardrb`, the CI matrix, and the branch/PR workflow
(one task → one branch → one PR).

## License

MIT — see [LICENSE.txt](LICENSE.txt).
