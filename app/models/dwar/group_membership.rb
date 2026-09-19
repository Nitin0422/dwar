# frozen_string_literal: true

module Dwar
  class GroupMembership < ApplicationRecord
    belongs_to :group
    belongs_to :actor, polymorphic: true

    validates :actor_id, uniqueness: {scope: %i[group_id actor_type]}
  end
end
