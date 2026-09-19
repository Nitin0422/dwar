# frozen_string_literal: true

module Dwar
  class Flag < ApplicationRecord
    KEY_FORMAT = /\A[a-z0-9_\/.-]+\z/

    enum :state, {
      disabled: "disabled",
      enabled: "enabled",
      percentage: "percentage",
      groups: "groups",
      groups_and_percentage: "groups_and_percentage"
    }, default: :disabled, validate: true

    has_many :flag_groups, dependent: :destroy
    has_many :groups, through: :flag_groups

    validates :key, presence: true, uniqueness: true, format: {with: KEY_FORMAT}

    # The percentage column is only meaningful for percentage-style states
    # (FR-3/F3 decision); every other state ignores it entirely.
    validates :percentage,
      numericality: {only_integer: true, in: 0..100},
      if: -> { percentage? || groups_and_percentage? }
  end
end
