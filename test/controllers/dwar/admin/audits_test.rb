# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class AuditsAdminTest < ActionDispatch::IntegrationTest
  def setup
    Dwar.reset_config
    Dwar.configure { |c| c.authorization = ->(_controller) { true } }
  end

  def teardown
    Dwar.reset_config
  end

  # AC2: every mutation writes exactly one audit row ----------------------
  test "flag create writes one create audit with snapshot summary" do
    assert_difference("Dwar::Audit.count", 1) do
      post "/dwar/admin/flags", params: {flag: {key: "trailed", state: "enabled"}}
    end

    assert_redirected_to "/dwar/admin/flags"
    audit = Dwar::Audit.last
    flag = Dwar::Flag.find_by!(key: "trailed")
    assert_equal "create", audit.action
    assert_equal "Dwar::Flag", audit.auditable_type
    assert_equal flag.id.to_s, audit.auditable_id
    assert_equal "trailed", audit.change_summary["key"]
    assert_equal "enabled", audit.change_summary["state"]
    assert_nil audit.actor_type
    assert_nil audit.actor_id
  end

  test "flag update writes one update audit with attribute diff" do
    flag = Dwar::Flag.create!(key: "mutable", state: "disabled")

    assert_difference("Dwar::Audit.count", 1) do
      patch "/dwar/admin/flags/#{flag.id}", params: {flag: {state: "enabled"}}
    end

    audit = Dwar::Audit.last
    assert_equal "update", audit.action
    assert_equal "Dwar::Flag", audit.auditable_type
    assert_equal flag.id.to_s, audit.auditable_id
    assert_equal({"from" => "disabled", "to" => "enabled"}, audit.change_summary["state"])
  end

  test "flag targeting change is audited as a flag update with group diff" do
    flag = Dwar::Flag.create!(key: "targeted", state: "groups")
    gone = Dwar::Group.create!(name: "gone")
    fresh = Dwar::Group.create!(name: "fresh")
    flag.groups << gone

    assert_difference("Dwar::Audit.count", 1) do
      patch "/dwar/admin/flags/#{flag.id}",
        params: {flag: {state: "groups", group_ids: [fresh.id]}}
    end

    audit = Dwar::Audit.last
    assert_equal "update", audit.action
    assert_equal ["fresh"], audit.change_summary["groups"]["added"]
    assert_equal ["gone"], audit.change_summary["groups"]["removed"]
  end

  test "flag destroy writes one audit and cascade joins are not audited" do
    flag = Dwar::Flag.create!(key: "doomed", state: "disabled")
    group = Dwar::Group.create!(name: "doomed_group")
    Dwar::FlagGroup.create!(flag: flag, group: group)

    assert_difference("Dwar::Audit.count", 1) do
      assert_difference("Dwar::FlagGroup.count", -1) do
        delete "/dwar/admin/flags/#{flag.id}"
      end
    end

    assert_redirected_to "/dwar/admin/flags"
    audit = Dwar::Audit.last
    assert_equal "destroy", audit.action
    assert_equal "Dwar::Flag", audit.auditable_type
    assert_equal flag.id.to_s, audit.auditable_id
    assert_equal "doomed", audit.change_summary["key"]
  end

  test "group create update and destroy each write one audit" do
    assert_difference("Dwar::Audit.count", 1) do
      post "/dwar/admin/groups", params: {group: {name: "beta", description: "d"}}
    end
    group = Dwar::Group.find_by!(name: "beta")
    assert_equal "create", Dwar::Audit.last.action
    assert_equal "Dwar::Group", Dwar::Audit.last.auditable_type

    assert_difference("Dwar::Audit.count", 1) do
      patch "/dwar/admin/groups/#{group.id}", params: {group: {name: "beta2"}}
    end
    audit = Dwar::Audit.last
    assert_equal "update", audit.action
    assert_equal({"from" => "beta", "to" => "beta2"}, audit.change_summary["name"])

    assert_difference("Dwar::Audit.count", 1) do
      delete "/dwar/admin/groups/#{group.id}"
    end
    assert_equal "destroy", Dwar::Audit.last.action
    assert_equal group.id.to_s, Dwar::Audit.last.auditable_id
  end

  test "membership add and remove each write one audit" do
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")

    assert_difference("Dwar::Audit.count", 1) do
      post "/dwar/admin/groups/#{group.id}/memberships",
        params: {membership: {actor_id: user.id, actor_type: "User"}}
    end
    assert_redirected_to "/dwar/admin/groups/#{group.id}/memberships"
    audit = Dwar::Audit.last
    membership = Dwar::GroupMembership.last
    assert_equal "create", audit.action
    assert_equal "Dwar::GroupMembership", audit.auditable_type
    assert_equal membership.id.to_s, audit.auditable_id
    assert_equal "beta", audit.change_summary["group"]
    assert_equal "User", audit.change_summary["actor_type"]

    assert_difference("Dwar::Audit.count", 1) do
      delete "/dwar/admin/groups/#{group.id}/memberships/#{membership.id}"
    end
    assert_equal "destroy", Dwar::Audit.last.action
    assert_equal membership.id.to_s, Dwar::Audit.last.auditable_id
  end

  test "failed validations write no audit rows" do
    flag = Dwar::Flag.create!(key: "stays", state: "disabled")
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")
    Dwar::GroupMembership.create!(group: group, actor: user)

    assert_no_difference("Dwar::Audit.count") do
      post "/dwar/admin/flags", params: {flag: {key: ""}}
      assert_response :unprocessable_entity

      patch "/dwar/admin/flags/#{flag.id}", params: {flag: {key: ""}}
      assert_response :unprocessable_entity

      post "/dwar/admin/groups", params: {group: {name: ""}}
      assert_response :unprocessable_entity

      post "/dwar/admin/groups/#{group.id}/memberships",
        params: {membership: {actor_id: user.id.to_s, actor_type: "User"}}
      assert_response :unprocessable_entity
    end
  end

  # AC3: who ---------------------------------------------------------------
  test "audit_actor populates actor columns" do
    admin = User.create!(name: "admin")
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.audit_actor = ->(_controller) { admin }
    end

    post "/dwar/admin/flags", params: {flag: {key: "who"}}
    assert_redirected_to "/dwar/admin/flags"

    audit = Dwar::Audit.last
    assert_equal "User", audit.actor_type
    assert_equal admin.id.to_s, audit.actor_id

    get "/dwar/admin/audits"
    assert_response :success
    assert_includes response.body, "User ##{admin.id}"
  end

  test "null actor renders an em dash in the audit list" do
    post "/dwar/admin/flags", params: {flag: {key: "wholess"}}
    assert_redirected_to "/dwar/admin/flags"

    get "/dwar/admin/audits"
    assert_response :success
    assert_includes response.body, "—"
  end

  test "raising audit_actor fails loud with no write committed" do
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.audit_actor = ->(_controller) { raise "audit hook boom" }
    end

    # NOTE: count assertions wrap the assert_raises instead of nesting
    # inside it — Rails 8.1's assert_no_difference treats any block raise
    # as its own failure before an outer assert_raises can catch it.
    before_flags = Dwar::Flag.count
    before_audits = Dwar::Audit.count
    error = assert_raises(RuntimeError) do
      post "/dwar/admin/flags", params: {flag: {key: "never"}}
    end

    assert_equal "audit hook boom", error.message
    assert_equal before_flags, Dwar::Flag.count
    assert_equal before_audits, Dwar::Audit.count
    assert_nil Dwar::Flag.find_by(key: "never")
  end

  # AC5: same-transaction failure semantics ----------------------------------
  test "audit failure rolls back a flag create and surfaces" do
    before_flags = Dwar::Flag.count
    before_audits = Dwar::Audit.count

    Dwar::Audit.stub(:create!, ->(*_args) { raise "audit boom" }) do
      error = assert_raises(RuntimeError) do
        post "/dwar/admin/flags", params: {flag: {key: "rolled_back"}}
      end
      assert_equal "audit boom", error.message
    end

    assert_equal before_flags, Dwar::Flag.count
    assert_equal before_audits, Dwar::Audit.count
    assert_nil Dwar::Flag.find_by(key: "rolled_back")
  end

  test "audit failure rolls back a flag destroy and surfaces" do
    flag = Dwar::Flag.create!(key: "survivor", state: "disabled")
    before_audits = Dwar::Audit.count

    Dwar::Audit.stub(:create!, ->(*_args) { raise "audit boom" }) do
      error = assert_raises(RuntimeError) do
        delete "/dwar/admin/flags/#{flag.id}"
      end
      assert_equal "audit boom", error.message
    end

    assert Dwar::Flag.exists?(flag.id)
    assert_equal before_audits, Dwar::Audit.count
  end

  test "audit failure rolls back a membership add and surfaces" do
    group = Dwar::Group.create!(name: "beta")
    user = User.create!(name: "alice")
    before_memberships = Dwar::GroupMembership.count
    before_audits = Dwar::Audit.count

    Dwar::Audit.stub(:create!, ->(*_args) { raise "audit boom" }) do
      error = assert_raises(RuntimeError) do
        post "/dwar/admin/groups/#{group.id}/memberships",
          params: {membership: {actor_id: user.id, actor_type: "User"}}
      end
      assert_equal "audit boom", error.message
    end

    assert_equal before_memberships, Dwar::GroupMembership.count
    assert_equal before_audits, Dwar::Audit.count
  end

  # AC4: index -----------------------------------------------------------------
  test "index returns 200 newest-first with readable rows" do
    post "/dwar/admin/flags", params: {flag: {key: "first"}}
    assert_redirected_to "/dwar/admin/flags"
    post "/dwar/admin/flags", params: {flag: {key: "second"}}
    assert_redirected_to "/dwar/admin/flags"

    get "/dwar/admin/audits"

    assert_response :success
    assert_includes response.body, "Audit trail"
    assert_includes response.body, "create"
    assert_includes response.body, "second"
    assert_includes response.body, "first"
    assert_includes response.body, "<table>"
    # Compare the record-label cells (not bare substrings: the page note
    # itself contains the word "first").
    assert response.body.index("<td>second</td>") < response.body.index("<td>first</td>"),
      "expected the newer audit to render before the older one"
  end

  test "index shows update diffs readably" do
    flag = Dwar::Flag.create!(key: "readable", state: "disabled")
    patch "/dwar/admin/flags/#{flag.id}", params: {flag: {state: "enabled"}}

    get "/dwar/admin/audits"

    assert_response :success
    assert_includes response.body, "update"
    assert_includes response.body, "readable"
    assert_includes response.body, "disabled"
    assert_includes response.body, "enabled"
  end

  test "index with no entries shows the empty state" do
    get "/dwar/admin/audits"

    assert_response :success
    assert_includes response.body, "No audit entries yet."
  end

  test "index falls back gracefully for destroyed records" do
    post "/dwar/admin/flags", params: {flag: {key: "gone"}}
    assert_redirected_to "/dwar/admin/flags"
    flag = Dwar::Flag.find_by!(key: "gone")
    delete "/dwar/admin/flags/#{flag.id}"
    assert_redirected_to "/dwar/admin/flags"

    get "/dwar/admin/audits"

    assert_response :success
    assert_includes response.body, "(removed)"
  end

  test "index is reachable from the nav" do
    get "/dwar/admin/flags"

    assert_response :success
    assert_match %r{href="/dwar/admin/audits}, response.body
  end

  # Fail-closed ---------------------------------------------------------------
  test "nil authorization hook denies the audit list with 403" do
    Dwar.reset_config

    get "/dwar/admin/audits"

    assert_response :forbidden
    assert_includes response.body, "Dwar admin is disabled"
  end

  test "false authorization hook denies the audit list with 403" do
    Dwar.configure { |c| c.authorization = ->(_controller) { false } }

    get "/dwar/admin/audits"

    assert_response :forbidden
  end

  test "denied writes leave no audit rows" do
    flag = Dwar::Flag.create!(key: "guarded", state: "disabled")
    Dwar.configure { |c| c.authorization = ->(_controller) { false } }

    assert_no_difference(["Dwar::Flag.count", "Dwar::Audit.count"]) do
      post "/dwar/admin/flags", params: {flag: {key: "nope"}}
      assert_response :forbidden

      patch "/dwar/admin/flags/#{flag.id}", params: {flag: {state: "enabled"}}
      assert_response :forbidden

      delete "/dwar/admin/flags/#{flag.id}"
      assert_response :forbidden
    end
  end
end
