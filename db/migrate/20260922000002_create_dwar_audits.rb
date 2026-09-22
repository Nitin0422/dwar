# frozen_string_literal: true

# T13: audit trail. One row per admin write (flag/group create/update/
# destroy, membership add/remove), recorded in the same transaction as the
# write itself so an audit failure rolls the write back instead of being
# silently swallowed.
#
# No foreign keys by design: audited records are routinely destroyed (their
# audit rows must survive as the trail), and membership actors live in the
# host application outside this engine's tables. The polymorphic references
# are plain strings so integer, UUID, and other host key shapes all fit.
class CreateDwarAudits < ActiveRecord::Migration[7.1]
  def change
    create_table :dwar_audits do |t|
      t.string :auditable_type, null: false
      t.string :auditable_id, null: false
      t.string :action, null: false
      t.text :change_summary
      t.string :actor_type
      t.string :actor_id
      t.timestamps
    end
    add_index :dwar_audits, [:auditable_type, :auditable_id]
    add_index :dwar_audits, :created_at
    add_index :dwar_audits, [:actor_type, :actor_id]
  end
end
