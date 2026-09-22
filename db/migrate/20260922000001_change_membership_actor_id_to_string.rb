# frozen_string_literal: true

# T12: host actor keys may be UUIDs or other string keys, so the polymorphic
# actor_id must be a string column. Integers keep working: ActiveRecord
# type-casts query binds to the column type, and Bucketing/Evaluator/Cache
# normalize ids with to_s, so `where(actor_id: 42)` still matches a stored
# "42". Matching stays verbatim — "42" != "042" — pinned by tests.
#
# Reversible by design (up/down, not change: change_column is irreversible
# inside def change). On PostgreSQL the up direction needs no USING clause
# (integer -> varchar has an implicit cast, verified against PG semantics
# for ALTER TYPE on a populated table), while the down direction needs an
# explicit USING cast (varchar -> integer has no implicit ALTER TYPE cast).
# Rolling back while non-numeric actor_ids are present raises from the
# database instead of silently truncating — that is intentional.
class ChangeMembershipActorIdToString < ActiveRecord::Migration[7.1]
  def up
    change_column :dwar_group_memberships, :actor_id, :string, null: false
  end

  def down
    if connection.adapter_name == "PostgreSQL"
      connection.execute(<<~SQL.squish)
        ALTER TABLE dwar_group_memberships
        ALTER COLUMN actor_id TYPE integer USING actor_id::integer
      SQL
    else
      change_column :dwar_group_memberships, :actor_id, :integer, null: false
    end
  end
end
