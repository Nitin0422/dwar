# frozen_string_literal: true

require "test_helper"

class GroupTest < ActiveSupport::TestCase
  test "name presence is required" do
    group = Dwar::Group.new
    refute group.valid?
    assert_includes group.errors[:name], "can't be blank"
  end

  test "name must be unique" do
    Dwar::Group.create!(name: "beta")
    duplicate = Dwar::Group.new(name: "beta")
    refute duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "description is optional" do
    assert Dwar::Group.new(name: "beta", description: "the beta group").valid?
    assert Dwar::Group.new(name: "gamma").valid?
  end

  test "destroying a group removes its flag_groups and memberships" do
    group = Dwar::Group.create!(name: "beta")
    flag = Dwar::Flag.create!(key: "user.feature")
    user = User.create!(name: "alice")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    Dwar::GroupMembership.create!(group: group, actor: user)

    assert_equal 1, Dwar::FlagGroup.count
    assert_equal 1, Dwar::GroupMembership.count

    group.destroy

    assert_equal 0, Dwar::FlagGroup.count
    assert_equal 0, Dwar::GroupMembership.count
    assert Dwar::Flag.exists?(flag.id)
    assert User.exists?(user.id)
  end
end
