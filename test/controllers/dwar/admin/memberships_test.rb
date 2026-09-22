# frozen_string_literal: true

require "test_helper"

class MembershipsAdminTest < ActionDispatch::IntegrationTest
  def setup
    Dwar.reset_config
    Dwar::Cache.reset! if defined?(Dwar::Cache)
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(_query) { [] }
      c.user_display = :to_s
    end
  end

  def teardown
    Dwar::Cache.reset! if defined?(Dwar::Cache)
    Dwar.reset_config
  end

  def members_path(group)
    "/dwar/admin/groups/#{group.id}/memberships"
  end

  # AC: list renders current members with user_display labels, plus the
  # group header, back link, picker form and guarded picker init.
  test "index lists members with user_display labels" do
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_display = :name
    end
    group = Dwar::Group.create!(name: "beta")
    alice = User.create!(name: "alice")
    bob = User.create!(name: "bob")
    Dwar::GroupMembership.create!(group: group, actor: alice)
    Dwar::GroupMembership.create!(group: group, actor: bob)

    get members_path(group)

    assert_response :success
    assert_includes response.body, "Members of"
    assert_includes response.body, "beta"
    assert_includes response.body, "alice"
    assert_includes response.body, "bob"
    assert_includes response.body, "Back to groups"
    assert_includes response.body, "Add member"
    assert_includes response.body, "data-dwar-user-picker"
    assert_includes response.body, 'name="membership[actor_id]"'
    assert_includes response.body, 'name="membership[actor_type]"'
    assert_includes response.body, "Remove"
    assert_includes response.body, "data-turbo-confirm"
  end

  test "index with no members shows empty state" do
    group = Dwar::Group.create!(name: "empty")

    get members_path(group)

    assert_response :success
    assert_includes response.body, "No members yet."
  end

  # AC: adding a picker result persists a GroupMembership and redirects.
  test "create persists a membership and redirects to the member list" do
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")

    assert_difference("Dwar::GroupMembership.count", 1) do
      post members_path(group), params: {membership: {actor_id: user.id, actor_type: "User"}}
    end

    assert_redirected_to members_path(group)
    follow_redirect!
    assert_response :success
  end

  # Actor_type defaults to User when the hidden field is blank or absent.
  test "create defaults blank actor_type to User" do
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")

    assert_difference("Dwar::GroupMembership.count", 1) do
      post members_path(group), params: {membership: {actor_id: user.id, actor_type: ""}}
    end

    assert_redirected_to members_path(group)
    assert_equal "User", Dwar::GroupMembership.last.actor_type
  end

  # AC: duplicates are rejected visibly (422, count unchanged).
  test "create with duplicate membership returns 422 with visible error" do
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")
    Dwar::GroupMembership.create!(group: group, actor: user)

    assert_no_difference("Dwar::GroupMembership.count") do
      post members_path(group), params: {membership: {actor_id: user.id.to_s, actor_type: "User"}}
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "has already been taken"
  end

  # AC: blank actor id is rejected with 422, never a 500.
  test "create with blank actor_id returns 422" do
    group = Dwar::Group.create!(name: "beta")

    assert_no_difference("Dwar::GroupMembership.count") do
      post members_path(group), params: {membership: {actor_id: "", actor_type: "User"}}
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "must exist"
  end

  test "create with missing membership param returns 422" do
    group = Dwar::Group.create!(name: "beta")

    assert_no_difference("Dwar::GroupMembership.count") do
      post members_path(group)
    end

    assert_response :unprocessable_entity
  end

  # The posted actor_type is allowlisted: real ActiveRecord classes pass,
  # arbitrary constants and garbage 422 without instantiating anything.
  test "create with non-actor class name returns 422" do
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")

    assert_no_difference("Dwar::GroupMembership.count") do
      post members_path(group), params: {membership: {actor_id: user.id, actor_type: "String"}}
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "is invalid"
  end

  test "create with unresolvable actor_type returns 422" do
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")

    assert_no_difference("Dwar::GroupMembership.count") do
      post members_path(group), params: {membership: {actor_id: user.id, actor_type: "Nope::Nah"}}
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "is invalid"
  end

  # H2: engine-internal ActiveRecord classes are never valid actors — the
  # picker only offers host user records, so Dwar::* types 422 instead of
  # persisting engine-model memberships.
  test "create with Dwar::Flag actor_type returns 422" do
    group = Dwar::Group.create!(name: "beta")
    flag = Dwar::Flag.create!(key: "feature.x", state: "disabled")

    assert_no_difference("Dwar::GroupMembership.count") do
      post members_path(group), params: {membership: {actor_id: flag.id, actor_type: "Dwar::Flag"}}
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "is invalid"
  end

  test "create with Dwar::Group actor_type returns 422" do
    group = Dwar::Group.create!(name: "beta")
    other = Dwar::Group.create!(name: "gamma")

    assert_no_difference("Dwar::GroupMembership.count") do
      post members_path(group), params: {membership: {actor_id: other.id, actor_type: "Dwar::Group"}}
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "is invalid"
  end

  test "create with ActiveRecord internal actor_type returns 422" do
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")

    assert_no_difference("Dwar::GroupMembership.count") do
      post members_path(group),
        params: {membership: {actor_id: user.id, actor_type: "ActiveRecord::SchemaMigration"}}
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "is invalid"
  end

  # Unknown group/member ids 404 via the Rails default (RecordNotFound).
  test "index with unknown group returns 404" do
    get "/dwar/admin/groups/999999/memberships"

    assert_response :not_found
  end

  test "create with unknown group returns 404" do
    user = User.create!(name: "alice")

    assert_no_difference("Dwar::GroupMembership.count") do
      post "/dwar/admin/groups/999999/memberships",
        params: {membership: {actor_id: user.id, actor_type: "User"}}
    end

    assert_response :not_found
  end

  test "destroy with unknown group returns 404" do
    delete "/dwar/admin/groups/999999/memberships/1"

    assert_response :not_found
  end

  test "destroy with unknown membership returns 404" do
    group = Dwar::Group.create!(name: "beta")

    delete "#{members_path(group)}/999999"

    assert_response :not_found
  end

  # AC: removing deletes the membership and redirects to the member list.
  test "destroy deletes the membership and redirects" do
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")
    membership = Dwar::GroupMembership.create!(group: group, actor: user)

    assert_difference("Dwar::GroupMembership.count", -1) do
      delete "#{members_path(group)}/#{membership.id}"
    end

    assert_redirected_to members_path(group)
    follow_redirect!
    assert_response :success
    assert_includes response.body, "No members yet."
  end

  # Destroy is scoped to the group: a membership id from another group 404s
  # instead of deleting across groups.
  test "destroy does not delete a membership from another group" do
    group = Dwar::Group.create!(name: "beta")
    other = Dwar::Group.create!(name: "gamma")
    user = User.create!(name: "alice")
    membership = Dwar::GroupMembership.create!(group: other, actor: user)

    assert_no_difference("Dwar::GroupMembership.count") do
      delete "#{members_path(group)}/#{membership.id}"
    end

    assert_response :not_found
  end

  # Auth regression: fail closed when no hook is configured.
  test "nil authorization hook denies memberships index with 403" do
    Dwar.reset_config
    group = Dwar::Group.create!(name: "beta")

    get members_path(group)

    assert_response :forbidden
    assert_includes response.body, "Dwar admin is disabled"
  end

  test "false authorization hook denies create with 403 and no record" do
    Dwar.configure { |c| c.authorization = ->(_controller) { false } }
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")

    assert_no_difference("Dwar::GroupMembership.count") do
      post members_path(group), params: {membership: {actor_id: user.id, actor_type: "User"}}
    end

    assert_response :forbidden
  end

  test "false authorization hook denies destroy with 403 and no delete" do
    Dwar.configure { |c| c.authorization = ->(_controller) { false } }
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")
    membership = Dwar::GroupMembership.create!(group: group, actor: user)

    assert_no_difference("Dwar::GroupMembership.count") do
      delete "#{members_path(group)}/#{membership.id}"
    end

    assert_response :forbidden
  end

  # The member list never touches user_finder (the picker calls it
  # client-side), so it renders 200 with no finder configured.
  test "index renders 200 without user_finder configured" do
    Dwar.reset_config
    Dwar.configure { |c| c.authorization = ->(_controller) { true } }
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")
    Dwar::GroupMembership.create!(group: group, actor: user)

    get members_path(group)

    assert_response :success
  end

  # AC: a raising user_display blanks only that row — the page still 200s.
  test "index with raising user_display falls back and still returns 200" do
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_display = ->(_record) { raise "boom" }
    end
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")
    Dwar::GroupMembership.create!(group: group, actor: user)

    get members_path(group)

    assert_response :success
    assert_includes response.body, "User #"
  end

  # AC: members whose actor records no longer resolve render defensively.
  test "index with deleted actor renders fallback label without crashing" do
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")
    Dwar::GroupMembership.create!(group: group, actor: user)
    user.destroy!

    get members_path(group)

    assert_response :success
    assert_includes response.body, "(removed)"
  end

  # AC (FR-8 + T07): add/remove take effect on the very next enabled? call.
  # Transactional tests never fire after_commit (outer rollback), so reset!
  # simulates the commit boundary here. The real hook path — controller
  # writes invalidating via GroupMembership#invalidate_dwar_cache with no
  # manual reset — is proven by MembershipInvalidationTest.
  test "membership add and remove flip group-targeted evaluation immediately" do
    group = Dwar::Group.create!(name: "beta")
    flag = Dwar::Flag.create!(key: "feature.x", state: "groups")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "alice")

    refute Dwar.enabled?(flag.key, user)

    post members_path(group), params: {membership: {actor_id: user.id, actor_type: "User"}}
    assert_redirected_to members_path(group)
    Dwar::Cache.reset! if defined?(Dwar::Cache)

    assert Dwar.enabled?(flag.key, user)

    membership = Dwar::GroupMembership.find_by!(group: group, actor_type: "User", actor_id: user.id.to_s)
    delete "#{members_path(group)}/#{membership.id}"
    assert_redirected_to members_path(group)
    Dwar::Cache.reset! if defined?(Dwar::Cache)

    refute Dwar.enabled?(flag.key, user)
  end

  # AC: groups_and_percentage requires BOTH membership and bucket passing.
  test "groups_and_percentage member inside bucket resolves true" do
    group = Dwar::Group.create!(name: "beta")
    flag = Dwar::Flag.create!(key: "feature.y", state: "groups_and_percentage", percentage: 100)
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "alice")

    post members_path(group), params: {membership: {actor_id: user.id, actor_type: "User"}}
    assert_redirected_to members_path(group)
    Dwar::Cache.reset! if defined?(Dwar::Cache)

    assert Dwar.enabled?(flag.key, user)
  end

  test "groups_and_percentage member outside bucket resolves false" do
    group = Dwar::Group.create!(name: "beta")
    flag = Dwar::Flag.create!(key: "feature.z", state: "groups_and_percentage", percentage: 0)
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "alice")
    Dwar::GroupMembership.create!(group: group, actor: user)
    Dwar::Cache.reset! if defined?(Dwar::Cache)

    refute Dwar.enabled?(flag.key, user)
  end

  test "groups_and_percentage outsider resolves false even at 100 percent" do
    group = Dwar::Group.create!(name: "beta")
    flag = Dwar::Flag.create!(key: "feature.w", state: "groups_and_percentage", percentage: 100)
    Dwar::FlagGroup.create!(flag: flag, group: group)
    outsider = User.create!(name: "mallory")

    refute Dwar.enabled?(flag.key, outsider)
  end
end
