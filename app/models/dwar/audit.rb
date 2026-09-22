# frozen_string_literal: true

module Dwar
  # One row of the admin audit trail (T13): who changed what, when.
  #
  # Rows are written explicitly by the admin controllers in the same
  # transaction as the change (see Dwar::Auditing) — never from model
  # callbacks. Deliberately has no cache hooks: audit rows must never
  # invalidate the evaluation cache, and destroying an audited record
  # leaves its trail behind (no dependent: :destroy anywhere points here).
  class Audit < ApplicationRecord
    ACTIONS = %w[create update destroy].freeze

    serialize :change_summary, coder: JSON

    validates :auditable_type, :auditable_id, :action, presence: true
    validates :action, inclusion: {in: ACTIONS}

    # Newest-first for the admin list; id breaks created_at ties so rows
    # written in the same second still come out in write order.
    scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  end
end
