# frozen_string_literal: true

module Dwar
  class Group < ApplicationRecord
    has_many :flag_groups, dependent: :destroy
    has_many :flags, through: :flag_groups
    has_many :group_memberships, dependent: :destroy

    validates :name, presence: true, uniqueness: true

    # Write invalidation for the T07 evaluation cache: bumps the global
    # generation plus the versions of flags currently targeting this group.
    # After a destroy the joins are already cascade-deleted so no flag keys
    # resolve — the global bump alone still invalidates everything, which is
    # the coarse-and-correct guarantee. after_commit only, so rolled back
    # transactions invalidate nothing.
    after_commit :invalidate_dwar_cache, on: %i[create update destroy]

    private

    def invalidate_dwar_cache
      Dwar::Cache.bump_flags_for_groups([id])
    end
  end
end
