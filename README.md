# dwar

Dwar is a mountable Rails engine for feature flags. Define flags in a built-in
admin UI, roll them out to everyone, to a percentage of users, or to specific
groups of users, and check them from your application code with a single call:
`Dwar.enabled?(:my_flag, current_user)`. All flag state lives in your own
database — no external services, no JavaScript build step.

- **Requirements:** Rails `>= 7.1` · Ruby `>= 3.2`

## Install

Add the gem and install it:

```ruby
# Gemfile
gem "dwar"
```

```sh
bundle install
bin/rails generate dwar:install
bin/rails db:migrate
```

The generator copies Dwar's migrations into your app and creates
`config/initializers/dwar.rb` with every option shown and commented out.
Re-running it never duplicates migrations or overwrites your edits.

Mount the engine in `config/routes.rb`:

```ruby
mount Dwar::Engine => "/dwar"
```

Then open the admin UI at `http://localhost:3000/dwar`.

## Configure

Edit `config/initializers/dwar.rb`. The two settings most apps need are the
user picker (used when adding group members in the admin UI) and the admin
gate:

```ruby
Dwar.configure do |config|
  # How the admin user picker searches your users. Receives a query string,
  # returns user records. Keep the LIKE pattern sanitized, scoped, and capped:
  config.user_finder = ->(query) {
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    User.where("name LIKE ?", pattern).order(:name).limit(50)
  }
  config.user_display = :name

  # Who may open the admin UI. Without this, every admin request is denied:
  config.authorization = ->(controller) { controller.current_user.admin? }
end
```

See the full option list under [Configuration](#configuration) below.

## Use flags in your code

1. Open the admin UI and create a flag, e.g. `new_checkout`. New flags start
   disabled, so they evaluate to `false` right away.
2. Check the flag wherever you need the branch:

```ruby
if Dwar.enabled?(:new_checkout, current_user)
  render :new_checkout
else
  render :classic_checkout
end
```

Pass the signed-in user (or any object with a stable `id`) whenever the flag
might use percentage or group targeting. For a simple on/off flag, the actor
is optional:

```ruby
Dwar.enabled?(:maintenance_banner)                 # fully enabled => true
Dwar.enabled?(:new_checkout, current_user)          # percentage/group checks need an actor
```

Flag keys may contain lowercase letters, numbers, `_`, `/`, `.`, and `-`
(e.g. `checkout/new_flow`, `search-v2`).

## How flags work

Each flag is in exactly one state:

| State | Meaning |
|---|---|
| `disabled` | Off for everyone. This is also a kill switch: flip a misbehaving flag back to `disabled` and it turns off immediately. |
| `enabled` | On for everyone, no user needed. |
| `percentage` | On for a fixed percentage of users (e.g. `25` = roughly a quarter of users). |
| `groups` | On only for users who belong to one of the flag's groups. |
| `groups_and_percentage` | On for users who belong to one of the flag's groups **and** fall inside the percentage. |

When you call `Dwar.enabled?`, the flag is resolved in this order:

1. Unknown flag key → `false`.
2. `disabled` → `false`.
3. `enabled` → `true`.
4. `percentage` → `true` only if a user was passed **and** that user's bucket is below the percentage.
5. `groups` → `true` only if a user was passed **and** they belong to a targeted group.
6. `groups_and_percentage` → `true` only if a user was passed **and** they belong to a targeted group **and** their bucket is below the percentage.

A few guarantees worth knowing:

- **Percentage rollouts are stable.** Every user is deterministically assigned
  a bucket from `0` to `99` based on the flag key and their user id, so the
  same user always lands in the same bucket. Raising a flag from 10% to 50%
  only adds users — nobody who had the feature loses it. `100` includes
  everyone, `0` includes no one.
- **Group targeting uses memberships.** Create a group (e.g. `beta_testers`),
  add users to it via the admin UI's user search, then attach the group to a
  flag. A user matches if they belong to any of the flag's groups.
- **Safe defaults.** An unknown flag returns `false`. Percentage and group
  checks without a user return `false`. `Dwar.enabled?` itself never raises —
  if something is unexpected, the feature simply stays off.
- **Changes take effect immediately.** Editing a flag in the admin UI applies
  to the very next `enabled?` call. No deploy, no restart.

## Admin UI

The admin UI is server-rendered and lives under the mount path (`/dwar` by
default). The home page is the flags list.

- **Flags** (`/admin/flags`): create, edit, and delete flags; search by key or
  description; each flag shows its state plus a summary of its percentage and
  targeted groups. Deleting a flag removes its group targeting as well.
- **Groups** (`/admin/groups`): create groups with unique names; the list
  shows member counts; deleting a group removes its memberships and detaches
  it from flags.
- **Memberships** (`/admin/groups/:id/memberships`): list a group's members,
  add members through the user search box, remove members. Adding the same
  user twice is rejected.
- **Audits** (`/admin/audits`): the newest 200 changes showing who changed
  what, and when.

Every admin page requires the `authorization` check to pass, otherwise it
returns a `403` error page.

## Configuration

All options are set in `config/initializers/dwar.rb` and are optional at boot.
`user_finder` is only required when you use the admin user search.

| Option | Type | Default | Meaning / example |
|---|---|---|---|
| `user_finder` | callable `->(query) { users }` | `nil` | How the admin user search finds records. Receives a query string, returns user records. Scope and cap the results inside the finder (e.g. `.order(:name).limit(50)`). Unset → the search endpoint returns a `503` error. Example: `config.user_finder = ->(query) { User.where("name LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%").order(:name).limit(50) }` |
| `user_display` | method name (`Symbol`/`String`) or callable | `:to_s` | How users are labeled in the admin UI. A method name is called on each record (`record.public_send(:name)`); a callable is called with the record. Falls back to `to_s` when unset or unknown. Example: `config.user_display = :name` |
| `admin_path` | `String` | `"/dwar"` | Where you expect the admin UI to live. Informational only — you still mount the engine yourself with `mount Dwar::Engine => "/dwar"`. Example: `config.admin_path = "/admin/dwar"` (and mount it there) |
| `authorization` | callable `->(controller) { bool }` | `nil` | Who may open the admin UI, evaluated with access to your controller helpers such as `current_user`. Unset → every admin request is denied. Example: `config.authorization = ->(controller) { controller.current_user.admin? }` |
| `cache` | Boolean | `true` | Whether `Dwar.enabled?` results are cached in memory. Set to `false` to re-evaluate on every call. |
| `audit_actor` | callable `->(controller) { user }` | `nil` | Who admin changes are attributed to in the audit trail. Unset → audits are recorded without an actor. Example: `config.audit_actor = ->(controller) { controller.current_user }` |

## License

MIT — see [LICENSE.txt](LICENSE.txt).
