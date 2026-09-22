# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class FlagsAdminTest < ActionDispatch::IntegrationTest
  def setup
    Dwar.reset_config
    Dwar.configure { |c| c.authorization = ->(_controller) { true } }
  end

  def teardown
    Dwar.reset_config
  end

  # CRUD: index ---------------------------------------------------------
  test "index returns 200 with flags table" do
    Dwar::Flag.create!(key: "alpha", state: "disabled")

    get "/dwar/admin/flags"

    assert_response :success
    assert_includes response.body, "alpha"
    assert_includes response.body, "<table>"
  end

  test "index shows state and targeting summary per row" do
    group = Dwar::Group.create!(name: "beta")
    Dwar::Flag.create!(key: "pct_flag", state: "percentage", percentage: 25)
    Dwar::Flag.create!(key: "grp_flag", state: "groups", groups: [group])
    Dwar::Flag.create!(key: "on_flag", state: "enabled")

    get "/dwar/admin/flags"

    assert_response :success
    assert_includes response.body, "percentage"
    assert_includes response.body, "25%"
    assert_includes response.body, "beta"
    assert_includes response.body, "Everyone"
  end

  test "new returns 200 with flag form" do
    get "/dwar/admin/flags/new"

    assert_response :success
    assert_includes response.body, "New flag"
    assert_includes response.body, "flag[key]"
  end

  test "edit returns 200 with prefilled form" do
    flag = Dwar::Flag.create!(key: "editable", description: "edit me", state: "disabled")

    get "/dwar/admin/flags/#{flag.id}/edit"

    assert_response :success
    assert_includes response.body, "Edit flag"
    assert_includes response.body, "edit me"
  end

  # CRUD: create --------------------------------------------------------
  test "create persists a disabled flag and redirects to index" do
    assert_difference("Dwar::Flag.count", 1) do
      post "/dwar/admin/flags", params: {flag: {key: "fresh", description: "brand new"}}
    end

    flag = Dwar::Flag.find_by(key: "fresh")
    assert_equal "disabled", flag.state
    assert_redirected_to "/dwar/admin/flags"
    follow_redirect!
    assert_includes response.body, "successfully created"
  end

  test "created flag evaluates to false" do
    post "/dwar/admin/flags", params: {flag: {key: "fresh_eval"}}

    assert_redirected_to "/dwar/admin/flags"
    refute Dwar.enabled?("fresh_eval")
  end

  test "create with blank key re-renders with 422, errors, and preserved values" do
    assert_no_difference("Dwar::Flag.count") do
      post "/dwar/admin/flags", params: {flag: {key: "", description: "kept text"}}
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "can&#39;t be blank"
    assert_includes response.body, "kept text"
  end

  test "create with badly formatted key re-renders with 422" do
    assert_no_difference("Dwar::Flag.count") do
      post "/dwar/admin/flags", params: {flag: {key: "Bad Key!"}}
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "is invalid"
  end

  test "create with out-of-range percentage re-renders with 422" do
    assert_no_difference("Dwar::Flag.count") do
      post "/dwar/admin/flags", params: {flag: {key: "bad_pct", state: "percentage", percentage: 101}}
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "bad_pct"
  end

  test "create normalizes out-of-range percentage for a disabled state to zero" do
    assert_difference("Dwar::Flag.count", 1) do
      post "/dwar/admin/flags", params: {flag: {key: "disabled_big", state: "disabled", percentage: 101}}
    end

    assert_redirected_to "/dwar/admin/flags"
    assert_equal 0, Dwar::Flag.find_by(key: "disabled_big").percentage
  end

  # CRUD: update --------------------------------------------------------
  test "update changes state, percentage, and groups then redirects" do
    flag = Dwar::Flag.create!(key: "mutable", state: "disabled")
    group = Dwar::Group.create!(name: "gamma")

    patch "/dwar/admin/flags/#{flag.id}",
      params: {flag: {state: "groups_and_percentage", percentage: 40, group_ids: [group.id]}}

    assert_redirected_to "/dwar/admin/flags"
    flag.reload
    assert_equal "groups_and_percentage", flag.state
    assert_equal 40, flag.percentage
    assert_equal [group.id], flag.group_ids
  end

  test "update with blank key re-renders with 422 and errors" do
    flag = Dwar::Flag.create!(key: "stays_valid", state: "disabled")

    patch "/dwar/admin/flags/#{flag.id}", params: {flag: {key: ""}}

    assert_response :unprocessable_entity
    assert_includes response.body, "can&#39;t be blank"
    assert_equal "stays_valid", flag.reload.key
  end

  test "update to a non-percentage state normalizes percentage to zero" do
    flag = Dwar::Flag.create!(key: "was_pct", state: "percentage", percentage: 50)

    patch "/dwar/admin/flags/#{flag.id}", params: {flag: {state: "disabled", percentage: 101}}

    assert_redirected_to "/dwar/admin/flags"
    assert_equal "disabled", flag.reload.state
    assert_equal 0, flag.reload.percentage
  end

  test "clearing all groups via blank group_ids removes targeting" do
    flag = Dwar::Flag.create!(key: "clear_groups", state: "groups")
    group = Dwar::Group.create!(name: "clear_beta")
    flag.groups << group
    member = User.create!(name: "clear_member")
    Dwar::GroupMembership.create!(group: group, actor: member)
    assert Dwar.enabled?("clear_groups", member)

    # The form's hidden field submits [""] when nothing is selected.
    patch "/dwar/admin/flags/#{flag.id}", params: {flag: {state: "groups", group_ids: [""]}}

    assert_redirected_to "/dwar/admin/flags"
    assert_equal [], flag.reload.group_ids
    refute Dwar.enabled?("clear_groups", member)
  end

  # CRUD: destroy -------------------------------------------------------
  test "destroy removes flag and its joins then redirects" do
    flag = Dwar::Flag.create!(key: "doomed", state: "disabled")
    group = Dwar::Group.create!(name: "doomed_group")
    Dwar::FlagGroup.create!(flag: flag, group: group)

    assert_difference("Dwar::Flag.count", -1) do
      assert_difference("Dwar::FlagGroup.count", -1) do
        delete "/dwar/admin/flags/#{flag.id}"
      end
    end

    assert_redirected_to "/dwar/admin/flags"
    follow_redirect!
    assert_includes response.body, "successfully destroyed"
  end

  test "destroy failure redirects with an alert instead of claiming success" do
    flag = Dwar::Flag.create!(key: "stubborn", state: "disabled")
    def flag.destroy
      false
    end

    Dwar::Flag.stub(:find, flag) do
      delete "/dwar/admin/flags/#{flag.id}"
    end

    assert_redirected_to "/dwar/admin/flags"
    follow_redirect!
    assert_includes response.body, "could not be destroyed"
    assert Dwar::Flag.exists?(flag.id)
  end

  test "index destroy control is a form button with confirmation prompt" do
    flag = Dwar::Flag.create!(key: "confirm_me", state: "disabled")

    get "/dwar/admin/flags"

    assert_response :success
    assert_includes response.body, "data-turbo-confirm"
    assert_match %r{<form[^>]*action="/dwar/admin/flags/#{flag.id}"}, response.body
    assert_includes response.body, 'value="delete"'
  end

  # All five states via the UI drive Dwar.enabled? ----------------------
  test "disabled state via UI evaluates false" do
    flag = Dwar::Flag.create!(key: "ui_disabled", state: "enabled")
    user = User.create!(name: "ui_disabled_user")

    patch "/dwar/admin/flags/#{flag.id}", params: {flag: {state: "disabled"}}

    assert_redirected_to "/dwar/admin/flags"
    refute Dwar.enabled?("ui_disabled", user)
    refute Dwar.enabled?("ui_disabled")
  end

  test "enabled state via UI evaluates true" do
    flag = Dwar::Flag.create!(key: "ui_enabled", state: "disabled")
    user = User.create!(name: "ui_enabled_user")

    patch "/dwar/admin/flags/#{flag.id}", params: {flag: {state: "enabled"}}

    assert_redirected_to "/dwar/admin/flags"
    assert Dwar.enabled?("ui_enabled", user)
    assert Dwar.enabled?("ui_enabled")
  end

  test "percentage 0 via UI evaluates false and 100 evaluates true" do
    zero = Dwar::Flag.create!(key: "ui_pct_zero", state: "disabled")
    hundred = Dwar::Flag.create!(key: "ui_pct_hundred", state: "disabled")
    user = User.create!(name: "ui_pct_user")

    patch "/dwar/admin/flags/#{zero.id}", params: {flag: {state: "percentage", percentage: 0}}
    patch "/dwar/admin/flags/#{hundred.id}", params: {flag: {state: "percentage", percentage: 100}}

    assert_redirected_to "/dwar/admin/flags"
    refute Dwar.enabled?("ui_pct_zero", user)
    assert Dwar.enabled?("ui_pct_hundred", user)
  end

  test "groups state via UI is membership-gated" do
    flag = Dwar::Flag.create!(key: "ui_groups", state: "disabled")
    group = Dwar::Group.create!(name: "ui_beta")
    member = User.create!(name: "ui_member")
    outsider = User.create!(name: "ui_outsider")
    Dwar::GroupMembership.create!(group: group, actor: member)

    patch "/dwar/admin/flags/#{flag.id}", params: {flag: {state: "groups", group_ids: [group.id]}}

    assert_redirected_to "/dwar/admin/flags"
    assert Dwar.enabled?("ui_groups", member)
    refute Dwar.enabled?("ui_groups", outsider)
  end

  test "groups_and_percentage via UI requires membership and bucket" do
    flag = Dwar::Flag.create!(key: "ui_gp", state: "disabled")
    group = Dwar::Group.create!(name: "ui_gp_beta")
    member = User.create!(name: "ui_gp_member")
    outsider = User.create!(name: "ui_gp_outsider")
    Dwar::GroupMembership.create!(group: group, actor: member)

    patch "/dwar/admin/flags/#{flag.id}",
      params: {flag: {state: "groups_and_percentage", percentage: 100, group_ids: [group.id]}}

    assert_redirected_to "/dwar/admin/flags"
    assert Dwar.enabled?("ui_gp", member)
    refute Dwar.enabled?("ui_gp", outsider)

    patch "/dwar/admin/flags/#{flag.id}",
      params: {flag: {state: "groups_and_percentage", percentage: 0, group_ids: [group.id]}}

    refute Dwar.enabled?("ui_gp", member)
  end

  # Search / filter -----------------------------------------------------
  test "search filters by key substring" do
    Dwar::Flag.create!(key: "searchable_checkout", state: "disabled")
    Dwar::Flag.create!(key: "unrelated_flag", state: "disabled")

    get "/dwar/admin/flags?q=checkout"

    assert_response :success
    assert_includes response.body, "searchable_checkout"
    assert_not_includes response.body, "unrelated_flag"
  end

  test "search filters by description substring" do
    Dwar::Flag.create!(key: "desc_one", description: "holiday promo rollout", state: "disabled")
    Dwar::Flag.create!(key: "desc_two", description: "ordinary flag", state: "disabled")

    get "/dwar/admin/flags?q=holiday"

    assert_response :success
    assert_includes response.body, "desc_one"
    assert_not_includes response.body, "desc_two"
  end

  test "no query returns all flags" do
    Dwar::Flag.create!(key: "all_one", state: "disabled")
    Dwar::Flag.create!(key: "all_two", state: "disabled")

    get "/dwar/admin/flags"

    assert_response :success
    assert_includes response.body, "all_one"
    assert_includes response.body, "all_two"
  end

  test "empty query returns all flags without error" do
    Dwar::Flag.create!(key: "empty_q", state: "disabled")

    get "/dwar/admin/flags?q="

    assert_response :success
    assert_includes response.body, "empty_q"
  end

  test "non-matching query renders empty state without error" do
    Dwar::Flag.create!(key: "something", state: "disabled")

    get "/dwar/admin/flags?q=zzz_no_match"

    assert_response :success
    assert_includes response.body, "No flags found."
    assert_not_includes response.body, "something"
  end

  test "search tolerates flags with NULL description" do
    Dwar::Flag.create!(key: "null_desc", state: "disabled")

    get "/dwar/admin/flags?q=null_desc"

    assert_response :success
    assert_includes response.body, "null_desc"
  end

  test "search escapes LIKE wildcards literally" do
    Dwar::Flag.create!(key: "literal_flag", state: "disabled")

    get "/dwar/admin/flags", params: {q: "%"}

    assert_response :success
    assert_includes response.body, "No flags found."
  end

  test "search matches description case-insensitively" do
    Dwar::Flag.create!(key: "ci_one", description: "Holiday Promo Rollout", state: "disabled")
    Dwar::Flag.create!(key: "ci_two", description: "ordinary flag", state: "disabled")

    get "/dwar/admin/flags", params: {q: "holiday"}

    assert_response :success
    assert_includes response.body, "ci_one"
    assert_not_includes response.body, "ci_two"
  end

  # Authorization regression (T08) --------------------------------------
  test "nil authorization hook denies flags admin with 403" do
    Dwar.reset_config

    get "/dwar/admin/flags"
    assert_response :forbidden

    get "/dwar/admin/flags/new"
    assert_response :forbidden
  end

  test "nil authorization hook denies flag writes with 403 and no side effects" do
    Dwar::Flag.create!(key: "guarded", state: "disabled")
    guarded = Dwar::Flag.find_by(key: "guarded")
    Dwar.reset_config

    post "/dwar/admin/flags", params: {flag: {key: "nope"}}
    assert_response :forbidden

    patch "/dwar/admin/flags/#{guarded.id}", params: {flag: {state: "enabled"}}
    assert_response :forbidden

    delete "/dwar/admin/flags/#{guarded.id}"
    assert_response :forbidden

    assert_nil Dwar::Flag.find_by(key: "nope")
    assert_equal "disabled", guarded.reload.state
    assert Dwar::Flag.exists?(guarded.id)
  end
end
