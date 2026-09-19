# frozen_string_literal: true

class CreateDwarTables < ActiveRecord::Migration[7.1]
  def change
    create_table :dwar_flags do |t|
      t.string :key, null: false
      t.string :description
      t.string :state, null: false, default: "disabled"
      t.integer :percentage, null: false, default: 0
      t.timestamps
    end
    add_index :dwar_flags, :key, unique: true

    create_table :dwar_groups do |t|
      t.string :name, null: false
      t.string :description
      t.timestamps
    end
    add_index :dwar_groups, :name, unique: true

    # Join table between flags and targeted groups. The references need the
    # explicit to_table: option — plain foreign_key: true would infer
    # "flags"/"groups" (without the dwar_ prefix) and break.
    create_table :dwar_flag_groups do |t|
      t.references :flag, null: false, foreign_key: {to_table: :dwar_flags, on_delete: :cascade}
      t.references :group, null: false, foreign_key: {to_table: :dwar_groups, on_delete: :cascade}
      t.timestamps
    end
    add_index :dwar_flag_groups, [:flag_id, :group_id], unique: true

    # Polymorphic memberships: the actor is owned by the host application
    # (FR-10), so no foreign key is created for the actor reference.
    create_table :dwar_group_memberships do |t|
      t.references :group, null: false, foreign_key: {to_table: :dwar_groups, on_delete: :cascade}
      t.references :actor, null: false, polymorphic: true
      t.timestamps
    end
    add_index :dwar_group_memberships, [:group_id, :actor_type, :actor_id], unique: true
  end
end
