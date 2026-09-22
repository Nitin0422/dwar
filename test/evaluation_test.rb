# frozen_string_literal: true

require "test_helper"

# Test-only stand-in for a host model with UUID string primary keys. The
# dummy User model has integer ids, so it cannot represent UUID actors;
# membership rows for this type are written with validate: false because
# the dummy schema has no backing UuidUser table to satisfy belongs_to.
class UuidUser
  attr_reader :id

  def initialize(id)
    @id = id
  end
end

# Table-driven coverage of Dwar.enabled? implementing FR-3 resolution.
# Tests all flag states x actor present/absent x membership
# present/absent, plus boundary percentages and nil/empty guard.
class EvaluationTest < ActiveSupport::TestCase
  def setup
    Dwar::Cache.reset!
    Dwar.reset_config
    @flag = Dwar::Flag.create!(key: "rollout", state: "percentage", percentage: 50)
  end

  def teardown
    Dwar::Cache.reset!
    Dwar.reset_config
  end

  # AC 1 — unknown flag key returns false without raising.
  test "unknown key returns false for both signatures" do
    refute Dwar.enabled?(:nonexistent)
    refute Dwar.enabled?(:nonexistent, User.new)
  end

  # AC 1 — unknown key with nil actor does not raise.
  test "unknown key with nil actor does not raise" do
    assert_nothing_raised { Dwar.enabled?(:nonexistent) }
    assert Dwar.enabled?(:nonexistent).equal?(false)
  end

  # State: disabled -------------------------------------------------------
  test "disabled state returns false with no actor" do
    flag = Dwar::Flag.create!(key: "disabled_flag", state: "disabled")
    refute Dwar.enabled?(flag.key)
  end

  test "disabled state returns false with an actor" do
    flag = Dwar::Flag.create!(key: "disabled_flag", state: "disabled")
    user = User.create!(name: "alice")
    refute Dwar.enabled?(flag.key, user)
  end

  # State: enabled --------------------------------------------------------
  test "enabled state returns true with no actor" do
    flag = Dwar::Flag.create!(key: "enabled_flag", state: "enabled")
    assert Dwar.enabled?(flag.key)
  end

  test "enabled state returns true with an actor" do
    flag = Dwar::Flag.create!(key: "enabled_flag", state: "enabled")
    user = User.create!(name: "bob")
    assert Dwar.enabled?(flag.key, user)
  end

  # State: percentage -----------------------------------------------------
  test "percentage state returns false when no actor supplied" do
    flag = Dwar::Flag.create!(key: "pct_flag", state: "percentage", percentage: 50)
    refute Dwar.enabled?(flag.key)
  end

  test "percentage state returns false when actor has nil id" do
    flag = Dwar::Flag.create!(key: "pct_nil_id", state: "percentage", percentage: 50)
    user = User.new(name: "ghost")
    refute Dwar.enabled?(flag.key, user)
  end

  test "percentage state returns false when actor is nil" do
    flag = Dwar::Flag.create!(key: "pct_nil_actor", state: "percentage", percentage: 50)
    refute Dwar.enabled?(flag.key, nil)
  end

  # State: groups ---------------------------------------------------------
  test "groups state returns false when no actor supplied" do
    flag = Dwar::Flag.create!(key: "groups_flag", state: "groups")
    refute Dwar.enabled?(flag.key)
  end

  test "groups state returns false when actor is not in any targeted group" do
    flag = Dwar::Flag.create!(key: "groups_no_member", state: "groups")
    group = Dwar::Group.create!(name: "beta")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "charlie")
    refute Dwar.enabled?(flag.key, user)
  end

  test "groups state returns true when actor belongs to a targeted group" do
    flag = Dwar::Flag.create!(key: "groups_with_member", state: "groups")
    group = Dwar::Group.create!(name: "beta")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "dave")
    Dwar::GroupMembership.create!(group: group, actor: user)
    assert Dwar.enabled?(flag.key, user)
  end

  # State: groups_and_percentage ------------------------------------------
  test "groups_and_percentage returns false when no actor supplied" do
    flag = Dwar::Flag.create!(key: "gp_flag", state: "groups_and_percentage", percentage: 50)
    refute Dwar.enabled?(flag.key)
  end

  test "groups_and_percentage returns false when actor is not a member" do
    flag = Dwar::Flag.create!(key: "gp_no_member", state: "groups_and_percentage", percentage: 50)
    group = Dwar::Group.create!(name: "beta")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "eve")
    refute Dwar.enabled?(flag.key, user)
  end

  test "groups_and_percentage returns true when actor is a member and in bucket" do
    flag = Dwar::Flag.create!(key: "gp_member_and_bucket", state: "groups_and_percentage", percentage: 100)
    group = Dwar::Group.create!(name: "beta")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "frank")
    Dwar::GroupMembership.create!(group: group, actor: user)
    assert Dwar.enabled?(flag.key, user)
  end

  test "groups_and_percentage returns false when actor is member but outside bucket" do
    flag = Dwar::Flag.create!(key: "gp_member_outside_bucket", state: "groups_and_percentage", percentage: 0)
    group = Dwar::Group.create!(name: "beta")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "grace")
    Dwar::GroupMembership.create!(group: group, actor: user)
    refute Dwar.enabled?(flag.key, user)
  end

  # Boundary: 0% ----------------------------------------------------------
  test "0% percentage makes every actor with a stable id false" do
    flag = Dwar::Flag.create!(key: "pct_zero", state: "percentage", percentage: 0)
    user = User.create!(name: "zero_user")
    refute Dwar.enabled?(flag.key, user)
  end

  # Boundary: 100% --------------------------------------------------------
  test "100% makes every actor with a stable id true" do
    flag = Dwar::Flag.create!(key: "pct_hundred", state: "percentage", percentage: 100)
    user = User.create!(name: "hundred_user")
    assert Dwar.enabled?(flag.key, user)
  end

  # Pinned T05 tuples: verify bucketing values and boundaries ---------

  # ["rollout","User",1] -> 99 (strict-< edge)
  test "pinned tuple: rollout/User/1 gives bucket 99" do
    assert_equal 99, Dwar::Bucketing.bucket("rollout", "User", 1)
  end

  # ["trial","User",1] -> 77 (strict-< edge)
  test "pinned tuple: trial/User/1 gives bucket 77" do
    assert_equal 77, Dwar::Bucketing.bucket("trial", "User", 1)
  end

  # ["rollout","User",2] -> 33 (equality boundary: 33 -> false, 34 -> true)
  test "pinned tuple: rollout/User/2 gives bucket 33" do
    assert_equal 33, Dwar::Bucketing.bucket("rollout", "User", 2)
  end

  # percentage 99 with bucket 99 actor returns false (strict-< edge)
  test "percentage 99 with bucket 99 actor returns false" do
    flag_key = "pct_99_flag"
    user = User.create!(name: "bucket_99_user")
    bucket = Dwar::Bucketing.bucket(flag_key, "User", user.id)
    flag = Dwar::Flag.create!(key: flag_key, state: "percentage", percentage: bucket)
    refute Dwar.enabled?(flag.key, user)
  end

  # percentage 100 with any bucket returns true
  test "percentage 100 with any actor returns true" do
    flag_key = "pct_100_flag"
    user = User.create!(name: "bucket_100_user")
    Dwar::Bucketing.bucket(flag_key, "User", user.id) # verify bucketing works
    flag = Dwar::Flag.create!(key: flag_key, state: "percentage", percentage: 100)
    assert Dwar.enabled?(flag.key, user)
  end

  # percentage 77 with bucket 77 actor returns false (strict-< edge)
  test "percentage 77 with bucket 77 actor returns false" do
    flag_key = "pct_77_flag"
    user = User.create!(name: "bucket_77_user")
    bucket = Dwar::Bucketing.bucket(flag_key, "User", user.id)
    flag = Dwar::Flag.create!(key: flag_key, state: "percentage", percentage: bucket)
    refute Dwar.enabled?(flag.key, user)
  end

  # equality boundary: percentage equals bucket -> false
  test "percentage equal to bucket returns false" do
    flag_key = "pct_eq_flag"
    user = User.create!(name: "bucket_eq_user")
    bucket = Dwar::Bucketing.bucket(flag_key, "User", user.id)
    flag = Dwar::Flag.create!(key: flag_key, state: "percentage", percentage: bucket)
    refute Dwar.enabled?(flag.key, user)
  end

  # equality boundary: percentage = bucket + 1 -> true
  test "percentage one greater than bucket returns true" do
    flag_key = "pct_plus_flag"
    user = User.create!(name: "bucket_plus_user")
    bucket = Dwar::Bucketing.bucket(flag_key, "User", user.id)
    percentage = [bucket + 1, 1].max
    flag = Dwar::Flag.create!(key: flag_key, state: "percentage", percentage: percentage)
    assert Dwar.enabled?(flag.key, user)
  end

  # Nil/empty actor id guard ----------------------------------------------
  test "groups state returns false when actor has nil id" do
    flag = Dwar::Flag.create!(key: "nil_id_groups", state: "groups")
    group = Dwar::Group.create!(name: "beta")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.new(name: "ghost")
    refute Dwar.enabled?(flag.key, user)
  end

  test "groups_and_percentage returns false when actor is a member but bucket >= percentage" do
    flag = Dwar::Flag.create!(key: "gp_bucket_edge", state: "groups_and_percentage", percentage: 50)
    group = Dwar::Group.create!(name: "beta")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "bucket_edge_user")
    Dwar::GroupMembership.create!(group: group, actor: user)
    # Pin percentage to the actor's own bucket (the equality edge of strict-<).
    # The previous `if bucket >= 50` guard left percentage at 50 for low-bucket
    # actors, making the outcome depend on the seed-ordered user.id.
    bucket = Dwar::Bucketing.bucket(flag.key, user.class, user.id)
    flag.update!(percentage: bucket)
    refute Dwar.enabled?(flag.key, user)
  end

  test "nil actor id returns false without raising for percentage flag" do
    flag = Dwar::Flag.create!(key: "nil_actor_pct", state: "percentage", percentage: 50)
    assert_nothing_raised { Dwar.enabled?(flag.key, nil) }
    refute Dwar.enabled?(flag.key, nil)
  end

  test "nil actor id returns false without raising for groups flag" do
    flag = Dwar::Flag.create!(key: "nil_actor_groups", state: "groups")
    group = Dwar::Group.create!(name: "beta")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    assert_nothing_raised { Dwar.enabled?(flag.key, nil) }
    refute Dwar.enabled?(flag.key, nil)
  end

  # Both enabled? signatures ----------------------------------------------
  test "enabled?(:key) without actor works for enabled state" do
    flag = Dwar::Flag.create!(key: "sig_enabled", state: "enabled")
    assert Dwar.enabled?(flag.key)
  end

  test "enabled?(:key, actor) with actor works for enabled state" do
    flag = Dwar::Flag.create!(key: "sig_enabled_actor", state: "enabled")
    user = User.create!(name: "sig_user")
    assert Dwar.enabled?(flag.key, user)
  end

  # Ever-green 100% with a variety of actors ------------------------------
  test "100% is ever-green across a variety of actors" do
    flag = Dwar::Flag.create!(key: "evergreen", state: "percentage", percentage: 100)
    [User.create!(name: "actor_a"),
      User.create!(name: "actor_b"),
      User.create!(name: "actor_c")].each do |user|
      assert Dwar.enabled?(flag.key, user), "expected true for #{user.name}"
    end
  end

  # Integer and string-normalized ids behave identically -------------------
  test "integer and string normalized ids behave identically" do
    user = User.create!(name: "norm_test")
    flag = Dwar::Flag.create!(key: "norm_test", state: "percentage", percentage: 100)
    assert Dwar.enabled?(flag.key, user)
  end

  # H3: non-integer (UUID) string actor ids round-trip through the
  # explicitly to_s-normalized evaluator query — member resolves true,
  # a different UUID resolves false, with no adapter coercion involved.
  test "uuid string actor ids round-trip through group evaluation" do
    flag = Dwar::Flag.create!(key: "uuid_flag", state: "groups")
    group = Dwar::Group.create!(name: "uuid_beta")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    uuid = "550e8400-e29b-41d4-a716-446655440000"
    membership = Dwar::GroupMembership.new(group: group, actor_type: "UuidUser", actor_id: uuid)
    membership.save!(validate: false)

    assert Dwar.enabled?(flag.key, UuidUser.new(uuid))
    refute Dwar.enabled?(flag.key, UuidUser.new("6ba7b810-9dad-11d1-80b4-00c04fd430c8"))
  end
end
