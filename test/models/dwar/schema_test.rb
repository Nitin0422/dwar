# frozen_string_literal: true

require "test_helper"

class SchemaTest < ActiveSupport::TestCase
  def connection
    ActiveRecord::Base.connection
  end

  test "models resolve to dwar_-prefixed tables via the namespace prefix" do
    assert_equal "dwar_flags", Dwar::Flag.table_name
    assert_equal "dwar_groups", Dwar::Group.table_name
    assert_equal "dwar_flag_groups", Dwar::FlagGroup.table_name
    assert_equal "dwar_group_memberships", Dwar::GroupMembership.table_name
  end

  test "unique indexes exist for keys and targeting pairs" do
    assert connection.indexes(:dwar_flags).any? { |i| i.columns == ["key"] && i.unique },
      "expected a unique index on dwar_flags.key"
    assert connection.indexes(:dwar_groups).any? { |i| i.columns == ["name"] && i.unique },
      "expected a unique index on dwar_groups.name"
    assert connection.indexes(:dwar_flag_groups).any? { |i| i.columns == ["flag_id", "group_id"] && i.unique },
      "expected a unique index on dwar_flag_groups(flag_id, group_id)"
    assert connection.indexes(:dwar_group_memberships).any? { |i| i.columns == ["group_id", "actor_type", "actor_id"] && i.unique },
      "expected a unique index on dwar_group_memberships(group_id, actor_type, actor_id)"
  end

  test "dwar_flags columns carry the expected nullability and defaults" do
    columns = connection.columns(:dwar_flags)

    description = columns.find { |column| column.name == "description" }
    assert description.null, "expected description to be nullable"

    state = columns.find { |column| column.name == "state" }
    refute state.null, "expected state to be not-null"
    assert_equal "disabled", state.default

    percentage = columns.find { |column| column.name == "percentage" }
    refute percentage.null, "expected percentage to be not-null"
    # Integer-column defaults are reported as an Integer on Rails 7.1/8.1 and
    # as a String on Rails 7.2/8.0; accept both representations.
    assert_includes [0, "0"], percentage.default, "expected percentage default to be 0"
  end

  test "foreign keys cascade from flag_groups and memberships to the dwar tables" do
    flag_group_fks = connection.foreign_keys(:dwar_flag_groups)
    assert flag_group_fks.any? { |fk| fk.to_table == "dwar_flags" && fk.on_delete.to_s.upcase == "CASCADE" },
      "expected dwarf_flag_groups.flag_id to cascade from dwar_flags"
    assert flag_group_fks.any? { |fk| fk.to_table == "dwar_groups" && fk.on_delete.to_s.upcase == "CASCADE" },
      "expected dwarf_flag_groups.group_id to cascade from dwar_groups"

    membership_fks = connection.foreign_keys(:dwar_group_memberships)
    assert membership_fks.any? { |fk| fk.to_table == "dwar_groups" && fk.on_delete.to_s.upcase == "CASCADE" },
      "expected dwar_group_memberships.group_id to cascade from dwar_groups"
  end
end
