# frozen_string_literal: true

require "test_helper"

# Non-transactional proof that membership writes through the admin
# controller invalidate the T07 evaluation cache via the GroupMembership
# after_commit hook — with no manual Cache.reset!.
#
# The transactional MembershipsAdminTest suite can never exercise
# after_commit (its outer transaction rolls back), so it simulates the
# commit boundary with Cache.reset!. This file reuses the T07 CacheTest
# harness instead: it opts out of transactional tests and cleans up
# explicitly, so controller writes commit for real and the hook fires.
class MembershipInvalidationTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  def setup
    clean_database!
    Dwar::Cache.reset! if defined?(Dwar::Cache)
    Dwar.reset_config
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(_query) { [] }
      c.user_display = :to_s
    end
  end

  def teardown
    clean_database!
    Dwar::Cache.reset! if defined?(Dwar::Cache)
    Dwar.reset_config
  end

  def members_path(group)
    "/dwar/admin/groups/#{group.id}/memberships"
  end

  # A committed controller create bumps the cache generation (the
  # after_commit hook) and the very next enabled? call sees the member —
  # no manual reset involved.
  test "controller create invalidates cached evaluation via after_commit" do
    group = Dwar::Group.create!(name: "beta")
    flag = Dwar::Flag.create!(key: "feature.hook", state: "groups")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "alice")

    refute Dwar.enabled?(flag.key, user)
    generation = Dwar::Cache.generation

    post members_path(group), params: {membership: {actor_id: user.id, actor_type: "User"}}
    assert_response :redirect

    assert_operator Dwar::Cache.generation, :>, generation
    assert Dwar.enabled?(flag.key, user),
      "expected committed controller create to flip evaluation without manual reset"
  end

  # Same hook path for removal: a committed controller destroy bumps the
  # generation and the next enabled? call sees the outsider.
  test "controller destroy invalidates cached evaluation via after_commit" do
    group = Dwar::Group.create!(name: "beta")
    flag = Dwar::Flag.create!(key: "feature.unhook", state: "groups")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "alice")
    membership = Dwar::GroupMembership.create!(group: group, actor: user)

    assert Dwar.enabled?(flag.key, user)
    generation = Dwar::Cache.generation

    delete "#{members_path(group)}/#{membership.id}"
    assert_response :redirect

    assert_operator Dwar::Cache.generation, :>, generation
    refute Dwar.enabled?(flag.key, user),
      "expected committed controller destroy to flip evaluation without manual reset"
  end

  private

  def clean_database!
    Dwar::GroupMembership.delete_all
    Dwar::FlagGroup.delete_all
    Dwar::Flag.delete_all
    Dwar::Group.delete_all
    # T13: controller writes commit audit rows for real here too, so they
    # need the same explicit cleanup as every other table above.
    Dwar::Audit.delete_all
    User.delete_all
  end
end
