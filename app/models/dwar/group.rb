# frozen_string_literal: true

module Dwar
  class Group < ApplicationRecord
    has_many :flag_groups, dependent: :destroy
    has_many :flags, through: :flag_groups
    has_many :group_memberships, dependent: :destroy

    validates :name, presence: true, uniqueness: true
  end
end
