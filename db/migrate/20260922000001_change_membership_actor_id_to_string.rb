# frozen_string_literal: true

# T12: host actor keys may be UUIDs or other string keys, so the polymorphic
# actor_id must be a string column. Integers keep working: ActiveRecord
# type-casts query binds to the column type, so `where(actor_id: 42)` still
# matches a stored "42", and Bucketing/Evaluator already normalize ids with
# to_s. Matching stays verbatim — "42" != "042" — pinned by tests.
class ChangeMembershipActorIdToString < ActiveRecord::Migration[7.1]
  def change
    change_column :dwar_group_memberships, :actor_id, :string, null: false
  end
end
