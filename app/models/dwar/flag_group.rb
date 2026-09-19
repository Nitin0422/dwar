# frozen_string_literal: true

module Dwar
  class FlagGroup < ApplicationRecord
    belongs_to :flag
    belongs_to :group

    validates :flag_id, uniqueness: {scope: :group_id}
  end
end
