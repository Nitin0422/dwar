# frozen_string_literal: true

module Dwar
  class FlagGroup < ApplicationRecord
    belongs_to :flag
    belongs_to :group

    validates :flag_id, uniqueness: {scope: :group_id}

    # Write invalidation for the T07 evaluation cache: (un)targeting a group
    # changes group-gated evaluation for the affected flags. after_commit
    # only, so rolled back transactions invalidate nothing.
    after_commit :invalidate_dwar_cache, on: %i[create update destroy]

    private

    def invalidate_dwar_cache
      ids = [flag_id]
      ids << previous_changes["flag_id"].first if previous_changes.key?("flag_id")
      Dwar::Cache.bump_flags_by_id(ids)
    end
  end
end
