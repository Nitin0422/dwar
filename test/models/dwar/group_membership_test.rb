# frozen_string_literal: true

require "test_helper"

class GroupMembershipTest < ActiveSupport::TestCase
  def setup
    @group = Dwar::Group.create!(name: "beta")
  end

  test "group and actor are required" do
    membership = Dwar::GroupMembership.new
    refute membership.valid?
    assert_includes membership.errors[:group], "must exist"
    assert_includes membership.errors[:actor], "must exist"
  end

  test "actor can be a host-side model (polymorphic)" do
    user = User.create!(name: "alice")
    membership = Dwar::GroupMembership.create!(group: @group, actor: user)

    assert_equal "User", membership.actor_type
    assert_equal user.id.to_s, membership.actor_id
  end

  test "duplicate actor in the same group is invalid" do
    user = User.create!(name: "alice")
    Dwar::GroupMembership.create!(group: @group, actor: user)

    duplicate = Dwar::GroupMembership.new(group: @group, actor: user)
    refute duplicate.valid?
    assert_includes duplicate.errors[:actor_id], "has already been taken"
  end

  test "same group can contain different actors" do
    alice = User.create!(name: "alice")
    bob = User.create!(name: "bob")
    Dwar::GroupMembership.create!(group: @group, actor: alice)

    assert Dwar::GroupMembership.new(group: @group, actor: bob).valid?
  end

  test "same actor can belong to different groups" do
    alice = User.create!(name: "alice")
    other = Dwar::Group.create!(name: "gamma")
    Dwar::GroupMembership.create!(group: @group, actor: alice)

    assert Dwar::GroupMembership.new(group: other, actor: alice).valid?
  end

  test "reloading the membership returns the same actor" do
    user = User.create!(name: "alice")
    membership = Dwar::GroupMembership.create!(group: @group, actor: user)

    assert_equal user, membership.reload.actor
    assert_equal user.id.to_s, membership.actor_id
  end

  # T12: actor_id is a string column so UUID/string host keys work; integer
  # ids store as their to_s form and dedupe across int/string spellings.
  test "actor_id stores as string and dedupes integer and string forms" do
    assert_equal :string, Dwar::GroupMembership.column_for_attribute(:actor_id).type

    user = User.create!(name: "alice")
    Dwar::GroupMembership.create!(group: @group, actor: user)

    string_spelling = Dwar::GroupMembership.new(
      group: @group, actor_type: "User", actor_id: user.id.to_s
    )
    refute string_spelling.valid?
    assert_includes string_spelling.errors[:actor_id], "has already been taken"
  end
end
