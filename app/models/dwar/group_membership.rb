# frozen_string_literal: true

module Dwar
  class GroupMembership < ApplicationRecord
    belongs_to :group
    belongs_to :actor, polymorphic: true

    validates :actor_id, uniqueness: {scope: %i[group_id actor_type]}

    # Write invalidation for the T07 evaluation cache: membership changes
    # flip group-gated evaluation for every flag targeting the group(s).
    # after_commit only, so rolled back transactions invalidate nothing.
    after_commit :invalidate_dwar_cache, on: %i[create update destroy]

    private

    def invalidate_dwar_cache
      ids = [group_id]
      ids << previous_changes["group_id"].first if previous_changes.key?("group_id")
      Dwar::Cache.bump_flags_for_groups(ids)
    end
  end
end
