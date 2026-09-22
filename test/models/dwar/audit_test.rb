# frozen_string_literal: true

require "test_helper"

class AuditTest < ActiveSupport::TestCase
  def setup
    Dwar.reset_config
    Dwar::Cache.reset! if defined?(Dwar::Cache)
  end

  def teardown
    Dwar::Cache.reset! if defined?(Dwar::Cache)
    Dwar.reset_config
  end

  # AC1: validation ----------------------------------------------------
  test "action must be create update or destroy" do
    %w[create update destroy].each do |action|
      audit = Dwar::Audit.new(auditable_type: "Dwar::Flag", auditable_id: "1", action: action)
      assert audit.valid?, "expected #{action.inspect} to be valid: #{audit.errors.full_messages}"
    end

    audit = Dwar::Audit.new(auditable_type: "Dwar::Flag", auditable_id: "1", action: "bogus")
    refute audit.valid?
    assert_includes audit.errors[:action], "is not included in the list"
  end

  test "auditable type id and action are required" do
    audit = Dwar::Audit.new
    refute audit.valid?
    assert_includes audit.errors[:auditable_type], "can't be blank"
    assert_includes audit.errors[:auditable_id], "can't be blank"
    assert_includes audit.errors[:action], "can't be blank"
  end

  # AC4: ordering -------------------------------------------------------
  test "newest_first orders by created_at desc" do
    old = Dwar::Audit.create!(
      auditable_type: "Dwar::Flag", auditable_id: "1", action: "create",
      created_at: 2.days.ago
    )
    fresh = Dwar::Audit.create!(
      auditable_type: "Dwar::Flag", auditable_id: "2", action: "create",
      created_at: 1.hour.ago
    )

    # Relative comparison (not exact table contents): the non-transactional
    # MembershipInvalidationTest commits rows that only its own cleanup
    # removes, so other rows may legitimately be present.
    ids = Dwar::Audit.newest_first.pluck(:id)
    assert ids.index(fresh.id) < ids.index(old.id)
  end

  test "newest_first breaks created_at ties by id desc (write order)" do
    moment = Time.current.change(usec: 0)
    first = Dwar::Audit.create!(
      auditable_type: "Dwar::Flag", auditable_id: "1", action: "create", created_at: moment
    )
    second = Dwar::Audit.create!(
      auditable_type: "Dwar::Flag", auditable_id: "2", action: "create", created_at: moment
    )

    ids = Dwar::Audit.newest_first.pluck(:id)
    assert ids.index(second.id) < ids.index(first.id)
  end

  # Recording surface ---------------------------------------------------
  test "record! persists auditable action summary and string id" do
    flag = Dwar::Flag.create!(key: "trailed", state: "disabled")

    audit = Dwar::Auditing.record!(
      auditable: flag, action: "create", change_summary: {"key" => "trailed"}
    )

    assert_equal "Dwar::Flag", audit.auditable_type
    assert_equal flag.id.to_s, audit.auditable_id
    assert_equal "create", audit.action
    assert_equal({"key" => "trailed"}, audit.reload.change_summary)
  end

  test "actor defaults to null" do
    flag = Dwar::Flag.create!(key: "actorless", state: "disabled")

    audit = Dwar::Auditing.record!(auditable: flag, action: "create", change_summary: {})

    assert_nil audit.actor_type
    assert_nil audit.actor_id
  end

  test "change_summary round-trips nested hashes through JSON" do
    flag = Dwar::Flag.create!(key: "json", state: "disabled")
    summary = {"state" => {"from" => "disabled", "to" => "enabled"}}

    audit = Dwar::Auditing.record!(auditable: flag, action: "update", change_summary: summary)

    assert_equal summary, audit.reload.change_summary
  end

  # Controller-only recording: direct model writes leave no trail --------
  test "direct model writes do not create audit rows" do
    assert_no_difference("Dwar::Audit.count") do
      flag = Dwar::Flag.create!(key: "direct", state: "disabled")
      group = Dwar::Group.create!(name: "direct")
      membership = Dwar::GroupMembership.create!(group: group, actor: User.create!(name: "u"))
      flag.update!(state: "enabled")
      group.update!(description: "x")
      membership.destroy!
      flag.destroy!
      group.destroy!
    end
  end

  # Destroying an audited record keeps its trail (no FKs, no cascade) ----
  test "destroying the audited record leaves audit rows behind" do
    flag = Dwar::Flag.create!(key: "doomed", state: "disabled")
    audit = Dwar::Auditing.record!(auditable: flag, action: "create", change_summary: {})

    flag.destroy!

    assert Dwar::Audit.exists?(audit.id)
  end

  # Audit rows must never invalidate the evaluation cache ----------------
  test "writing an audit row does not bump cache generation" do
    flag = Dwar::Flag.create!(key: "cached", state: "enabled")
    assert Dwar.enabled?("cached")
    before = Dwar::Cache.generation

    Dwar::Auditing.record!(auditable: flag, action: "update", change_summary: {})

    assert_equal before, Dwar::Cache.generation
  end

  # Targeting diff -------------------------------------------------------
  test "flag_update_summary diffs attributes and group targeting" do
    keep = Dwar::Group.create!(name: "keep")
    gone = Dwar::Group.create!(name: "gone")
    fresh = Dwar::Group.create!(name: "fresh")
    flag = Dwar::Flag.create!(key: "diff", state: "disabled", groups: [keep, gone])

    flag.update!(state: "groups", groups: [keep, fresh])
    summary = Dwar::Auditing.flag_update_summary(flag, [keep.id, gone.id])

    assert_equal({"from" => "disabled", "to" => "groups"}, summary["state"])
    assert_equal ["fresh"], summary["groups"]["added"]
    assert_equal ["gone"], summary["groups"]["removed"]
    refute summary.key?("key"), "unchanged attributes must be omitted"
    refute summary.key?("percentage"), "unchanged attributes must be omitted"
  end

  test "flag_update_summary is empty when nothing changed" do
    group = Dwar::Group.create!(name: "keep")
    flag = Dwar::Flag.create!(key: "same", state: "disabled", groups: [group])

    flag.update!(description: nil)
    summary = Dwar::Auditing.flag_update_summary(flag, [group.id])

    assert_empty summary
  end

  test "flag_update_summary falls back to id labels for missing groups" do
    flag = Dwar::Flag.create!(key: "ghost", state: "disabled")

    summary = Dwar::Auditing.flag_update_summary(flag, [999999])

    assert_equal ["#999999"], summary["groups"]["removed"]
    assert_equal [], summary["groups"]["added"]
  end

  test "flag destroy snapshot captures targeting before the destroy" do
    group = Dwar::Group.create!(name: "target")
    flag = Dwar::Flag.create!(key: "snap", state: "groups", groups: [group])

    snapshot = Dwar::Auditing.flag_snapshot(flag)

    assert_equal "snap", snapshot["key"]
    assert_equal ["target"], snapshot["groups"]
  end

  # Actor resolution ------------------------------------------------------
  test "resolve_actor returns null pair with no hook configured" do
    assert_equal [nil, nil], Dwar::Auditing.resolve_actor(Object.new)
  end

  test "resolve_actor returns null pair for a non-callable hook" do
    Dwar.configure { |c| c.audit_actor = "not-callable" }

    assert_equal [nil, nil], Dwar::Auditing.resolve_actor(Object.new)
  end

  test "resolve_actor returns null pair when the hook returns nil" do
    Dwar.configure { |c| c.audit_actor = ->(_controller) {} }

    assert_equal [nil, nil], Dwar::Auditing.resolve_actor(Object.new)
  end

  test "resolve_actor returns null pair when the hook returns false" do
    Dwar.configure { |c| c.audit_actor = ->(_controller) { false } }

    assert_equal [nil, nil], Dwar::Auditing.resolve_actor(Object.new)
  end

  test "resolve_actor normalizes an identity to type and string id" do
    user = User.create!(name: "admin")
    Dwar.configure { |c| c.audit_actor = ->(_controller) { user } }

    assert_equal ["User", user.id.to_s], Dwar::Auditing.resolve_actor(Object.new)
  end

  test "resolve_actor receives the controller as context" do
    captured = nil
    Dwar.configure do |c|
      c.audit_actor = ->(controller) {
        captured = controller
        nil
      }
    end
    controller = Object.new

    Dwar::Auditing.resolve_actor(controller)

    assert_same controller, captured
  end

  test "resolve_actor lets a raising hook propagate (fail-loud)" do
    Dwar.configure do |c|
      c.audit_actor = ->(_controller) { raise "audit hook boom" }
    end

    assert_raises(RuntimeError, "audit hook boom") do
      Dwar::Auditing.resolve_actor(Object.new)
    end
  end
end
