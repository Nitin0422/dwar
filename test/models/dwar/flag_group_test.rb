# frozen_string_literal: true

require "test_helper"

class FlagGroupTest < ActiveSupport::TestCase
  test "flag and group are required" do
    join = Dwar::FlagGroup.new
    refute join.valid?
    assert_includes join.errors[:flag], "must exist"
    assert_includes join.errors[:group], "must exist"
  end

  test "duplicate flag/group pair is invalid" do
    flag = Dwar::Flag.create!(key: "user.feature")
    group = Dwar::Group.create!(name: "beta")
    Dwar::FlagGroup.create!(flag: flag, group: group)

    duplicate = Dwar::FlagGroup.new(flag: flag, group: group)
    refute duplicate.valid?
    assert_includes duplicate.errors[:flag_id], "has already been taken"
  end

  test "same flag can target multiple groups" do
    flag = Dwar::Flag.create!(key: "user.feature")
    first = Dwar::Group.create!(name: "beta")
    second = Dwar::Group.create!(name: "gamma")
    Dwar::FlagGroup.create!(flag: flag, group: first)

    assert Dwar::FlagGroup.new(flag: flag, group: second).valid?
  end

  test "destroying the flag removes the join row" do
    flag = Dwar::Flag.create!(key: "user.feature")
    group = Dwar::Group.create!(name: "beta")
    Dwar::FlagGroup.create!(flag: flag, group: group)

    flag.destroy

    assert_equal 0, Dwar::FlagGroup.count
    assert Dwar::Group.exists?(group.id)
  end

  test "destroying the group removes the join row" do
    flag = Dwar::Flag.create!(key: "user.feature")
    group = Dwar::Group.create!(name: "beta")
    Dwar::FlagGroup.create!(flag: flag, group: group)

    group.destroy

    assert_equal 0, Dwar::FlagGroup.count
    assert Dwar::Flag.exists?(flag.id)
  end
end
