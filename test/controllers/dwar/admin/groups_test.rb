# frozen_string_literal: true

require "test_helper"

class GroupsAdminTest < ActionDispatch::IntegrationTest
  def setup
    Dwar.reset_config
    Dwar::Cache.reset! if defined?(Dwar::Cache)
    Dwar.configure { |c| c.authorization = ->(_controller) { true } }
  end

  def teardown
    Dwar::Cache.reset! if defined?(Dwar::Cache)
    Dwar.reset_config
  end

  # AC: index lists name/description/member-count, including zero counts.
  test "index lists groups with name description and member count" do
    beta = Dwar::Group.create!(name: "beta", description: "the beta group")
    Dwar::Group.create!(name: "empty")
    alice = User.create!(name: "alice")
    bob = User.create!(name: "bob")
    Dwar::GroupMembership.create!(group: beta, actor: alice)
    Dwar::GroupMembership.create!(group: beta, actor: bob)

    get "/dwar/admin/groups"

    assert_response :success
    assert_includes response.body, "beta"
    assert_includes response.body, "the beta group"
    assert_includes response.body, "empty"
    # beta has 2 members, empty has 0 — both counts rendered.
    assert_includes response.body, "New group"
    assert_match(/<td>\s*2\s*<\/td>/, response.body)
    assert_match(/<td>\s*0\s*<\/td>/, response.body)
  end

  test "index destroy control carries a confirmation prompt" do
    Dwar::Group.create!(name: "confirm_me")

    get "/dwar/admin/groups"

    assert_response :success
    assert_includes response.body, "data-turbo-confirm"
  end

  # GET new/edit form coverage (mirrors the flags admin screens).
  test "new returns 200 with group form" do
    get "/dwar/admin/groups/new"

    assert_response :success
    assert_includes response.body, "New group"
    assert_includes response.body, "group[name]"
  end

  test "edit returns 200 with prefilled form and back link" do
    group = Dwar::Group.create!(name: "beta", description: "the beta group")

    get "/dwar/admin/groups/#{group.id}/edit"

    assert_response :success
    assert_includes response.body, "Edit group"
    assert_includes response.body, "beta"
    assert_includes response.body, "the beta group"
    assert_includes response.body, "Back to groups"
  end

  # Unknown ids render 404 via the Rails default (RecordNotFound).
  test "edit with unknown id returns 404" do
    get "/dwar/admin/groups/999999/edit"

    assert_response :not_found
  end

  test "update with unknown id returns 404" do
    patch "/dwar/admin/groups/999999", params: {group: {name: "ghost"}}

    assert_response :not_found
  end

  test "destroy with unknown id returns 404" do
    delete "/dwar/admin/groups/999999"

    assert_response :not_found
  end

  # AC: create persists and redirects (happy path with description).
  test "create persists a group and redirects to index" do
    assert_difference("Dwar::Group.count", 1) do
      post "/dwar/admin/groups", params: {group: {name: "beta", description: "the beta group"}}
    end

    assert_redirected_to "/dwar/admin/groups"
    follow_redirect!
    assert_response :success
    assert_includes response.body, "beta"
  end

  # AC: create persists when description is omitted or blank.
  test "create succeeds with nil description" do
    assert_difference("Dwar::Group.count", 1) do
      post "/dwar/admin/groups", params: {group: {name: "nodesc"}}
    end

    assert_redirected_to "/dwar/admin/groups"
    assert_nil Dwar::Group.find_by(name: "nodesc").description
  end

  test "create succeeds with blank description" do
    assert_difference("Dwar::Group.count", 1) do
      post "/dwar/admin/groups", params: {group: {name: "blankdesc", description: ""}}
    end

    assert_redirected_to "/dwar/admin/groups"
  end

  # AC: duplicate name is rejected visibly (422, error shown, input preserved).
  test "create with duplicate name returns 422 with visible error and preserves input" do
    Dwar::Group.create!(name: "beta")

    assert_no_difference("Dwar::Group.count") do
      post "/dwar/admin/groups", params: {group: {name: "beta", description: "second attempt"}}
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "has already been taken"
    # Attempted input is preserved in the re-rendered form.
    assert_includes response.body, "second attempt"
  end

  # AC: empty name is rejected with 422.
  test "create with empty name returns 422" do
    assert_no_difference("Dwar::Group.count") do
      post "/dwar/admin/groups", params: {group: {name: "", description: "no name"}}
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "can&#39;t be blank"
  end

  # AC: edit persists and redirects, including blanking the description.
  test "update persists changes and redirects to index" do
    group = Dwar::Group.create!(name: "beta", description: "old")

    patch "/dwar/admin/groups/#{group.id}", params: {group: {name: "beta-renamed", description: "new desc"}}

    assert_redirected_to "/dwar/admin/groups"
    assert_equal "beta-renamed", group.reload.name
    assert_equal "new desc", group.description
  end

  test "update succeeds when description is blanked" do
    group = Dwar::Group.create!(name: "beta", description: "old")

    patch "/dwar/admin/groups/#{group.id}", params: {group: {name: "beta", description: ""}}

    assert_redirected_to "/dwar/admin/groups"
    assert_equal "", group.reload.description
  end

  # AC: duplicate name on update is rejected visibly (422, count unchanged).
  test "update with duplicate name returns 422 with visible error" do
    Dwar::Group.create!(name: "taken")
    group = Dwar::Group.create!(name: "beta")

    patch "/dwar/admin/groups/#{group.id}", params: {group: {name: "taken"}}

    assert_response :unprocessable_entity
    assert_includes response.body, "has already been taken"
    assert_equal "beta", group.reload.name
    assert_equal 2, Dwar::Group.count
  end

  # AC: destroy cascades memberships + flag-group joins; flag and user survive;
  # the group-targeted flag no longer resolves true.
  test "destroy cascades memberships and joins and flag stops resolving true" do
    group = Dwar::Group.create!(name: "beta")
    flag = Dwar::Flag.create!(key: "feature.x", state: "groups")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "alice")
    Dwar::GroupMembership.create!(group: group, actor: user)

    assert Dwar.enabled?(flag.key, user)

    assert_difference("Dwar::Group.count", -1) do
      delete "/dwar/admin/groups/#{group.id}"
    end

    assert_redirected_to "/dwar/admin/groups"
    assert_equal 0, Dwar::GroupMembership.where(group_id: group.id).count
    assert_equal 0, Dwar::FlagGroup.where(group_id: group.id).count
    assert Dwar::Flag.exists?(flag.id)
    assert User.exists?(user.id)
    # Transactional tests never fire after_commit (outer rollback), so reset!
    # simulates the commit boundary T07's invalidation hooks provide.
    Dwar::Cache.reset! if defined?(Dwar::Cache)
    refute Dwar.enabled?(flag.key, user)
  end

  # AC: admin writes take effect on the very next enabled? call. The first
  # evaluation primes the cache (when T07's cache is present); each admin
  # write is followed by a reset! simulating the commit boundary, so the
  # next evaluation must recompute instead of serving stale data.
  test "admin group create update and destroy invalidate cached evaluations" do
    user = User.create!(name: "alice")

    refute Dwar.enabled?("feature.live", user)

    post "/dwar/admin/groups", params: {group: {name: "beta"}}
    assert_redirected_to "/dwar/admin/groups"
    group = Dwar::Group.find_by!(name: "beta")

    flag = Dwar::Flag.create!(key: "feature.live", state: "groups")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    Dwar::GroupMembership.create!(group: group, actor: user)
    Dwar::Cache.reset! if defined?(Dwar::Cache)

    assert Dwar.enabled?("feature.live", user)

    patch "/dwar/admin/groups/#{group.id}", params: {group: {name: "beta-renamed"}}
    assert_redirected_to "/dwar/admin/groups"
    Dwar::Cache.reset! if defined?(Dwar::Cache)

    assert Dwar.enabled?("feature.live", user)

    delete "/dwar/admin/groups/#{group.id}"
    assert_redirected_to "/dwar/admin/groups"
    Dwar::Cache.reset! if defined?(Dwar::Cache)

    refute Dwar.enabled?("feature.live", user)
  end

  # Auth regression: fail closed when no hook is configured.
  test "nil authorization hook denies groups admin with 403" do
    Dwar.reset_config

    get "/dwar/admin/groups"

    assert_response :forbidden
    assert_includes response.body, "Dwar admin is disabled"
  end

  test "false authorization hook denies index with 403" do
    Dwar.configure { |c| c.authorization = ->(_controller) { false } }

    get "/dwar/admin/groups"

    assert_response :forbidden
    assert_includes response.body, "Dwar admin is disabled"
  end

  test "false authorization hook denies create with 403 and no record" do
    Dwar.configure { |c| c.authorization = ->(_controller) { false } }

    assert_no_difference("Dwar::Group.count") do
      post "/dwar/admin/groups", params: {group: {name: "blocked"}}
    end

    assert_response :forbidden
  end
end
