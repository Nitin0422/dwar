# frozen_string_literal: true

require "test_helper"

# Coverage for the T07 in-process evaluation cache (Dwar::Cache) and its
# write invalidation.
#
# These tests commit real rows: transactional tests never fire after_commit,
# which is exactly the mechanism under test, so this file opts out of
# transactional tests and cleans up explicitly instead. Every test starts
# from an empty cache and the default config (caching on).
class CacheTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def setup
    clean_database!
    Dwar::Cache.reset!
    Dwar.reset_config
  end

  def teardown
    clean_database!
    Dwar::Cache.reset!
    Dwar.reset_config
  end

  # -- hit / miss instrumentation -----------------------------------------

  test "repeated enabled? calls hit the cache after the first evaluation" do
    Dwar::Flag.create!(key: "cached", state: "enabled")
    user = User.create!(name: "reader")

    assert_equal 0, Dwar::Cache.misses
    assert Dwar.enabled?("cached")
    assert_equal 1, Dwar::Cache.misses
    assert_equal 0, Dwar::Cache.hits

    assert Dwar.enabled?("cached")
    assert_equal 1, Dwar::Cache.misses
    assert_equal 1, Dwar::Cache.hits

    # A different actor is a different cache entry.
    assert Dwar.enabled?("cached", user)
    assert_equal 2, Dwar::Cache.misses
    assert Dwar.enabled?("cached", user)
    assert_equal 2, Dwar::Cache.misses
    assert_equal 2, Dwar::Cache.hits
  end

  test "symbol and string flag keys share one cache entry" do
    Dwar::Flag.create!(key: "sym_flag", state: "enabled")

    assert Dwar.enabled?(:sym_flag)
    assert Dwar.enabled?("sym_flag")
    assert_equal 1, Dwar::Cache.misses
    assert_equal 1, Dwar::Cache.hits
  end

  # -- flag write invalidation ---------------------------------------------

  test "creating a flag invalidates the cached unknown-key miss" do
    refute Dwar.enabled?("late_flag")
    assert_equal 1, Dwar::Cache.misses

    Dwar::Flag.create!(key: "late_flag", state: "enabled")

    assert Dwar.enabled?("late_flag")
    assert_equal 2, Dwar::Cache.misses
  end

  test "disabled-to-enabled flip takes effect immediately" do
    flag = Dwar::Flag.create!(key: "flip_on", state: "disabled")
    refute Dwar.enabled?("flip_on")

    flag.update!(state: "enabled")

    assert Dwar.enabled?("flip_on")
  end

  test "enabled-to-disabled flip takes effect immediately" do
    flag = Dwar::Flag.create!(key: "flip_off", state: "enabled")
    assert Dwar.enabled?("flip_off")

    flag.update!(state: "disabled")

    refute Dwar.enabled?("flip_off")
    refute Dwar.enabled?("flip_off", User.create!(name: "flip_user"))
  end

  test "percentage change takes effect immediately across the bucket boundary" do
    # Pinned T05 tuple: bucket("rollout", "User", 1) == 99.
    user = User.create!(id: 1, name: "pinned_one")
    flag = Dwar::Flag.create!(key: "rollout", state: "percentage", percentage: 100)
    assert Dwar.enabled?("rollout", user)

    flag.update!(percentage: 99)

    refute Dwar.enabled?("rollout", user)

    flag.update!(percentage: 100)

    assert Dwar.enabled?("rollout", user)
  end

  test "destroying a flag invalidates the cached result" do
    flag = Dwar::Flag.create!(key: "doomed_flag", state: "enabled")
    assert Dwar.enabled?("doomed_flag")

    flag.destroy!

    refute Dwar.enabled?("doomed_flag")
  end

  # -- join / membership invalidation ---------------------------------------

  test "creating a flag-group targeting retargets evaluation immediately" do
    flag = Dwar::Flag.create!(key: "gflag", state: "groups")
    group = Dwar::Group.create!(name: "g1")
    user = User.create!(name: "member")
    Dwar::GroupMembership.create!(group: group, actor: user)

    refute Dwar.enabled?("gflag", user)

    Dwar::FlagGroup.create!(flag: flag, group: group)

    assert Dwar.enabled?("gflag", user)
  end

  test "destroying a flag-group untargets evaluation immediately" do
    flag = Dwar::Flag.create!(key: "ungflag", state: "groups")
    group = Dwar::Group.create!(name: "g2")
    user = User.create!(name: "member")
    Dwar::GroupMembership.create!(group: group, actor: user)
    Dwar::FlagGroup.create!(flag: flag, group: group)
    assert Dwar.enabled?("ungflag", user)

    Dwar::FlagGroup.find_by!(flag: flag, group: group).destroy!

    refute Dwar.enabled?("ungflag", user)
  end

  test "retargeting a flag-group to another group invalidates both flags" do
    flag_one = Dwar::Flag.create!(key: "flag_one", state: "groups")
    flag_two = Dwar::Flag.create!(key: "flag_two", state: "groups")
    group_one = Dwar::Group.create!(name: "group_one")
    group_two = Dwar::Group.create!(name: "group_two")
    user = User.create!(name: "member")
    Dwar::GroupMembership.create!(group: group_one, actor: user)
    Dwar::FlagGroup.create!(flag: flag_one, group: group_one)
    join = Dwar::FlagGroup.create!(flag: flag_two, group: group_two)
    assert Dwar.enabled?("flag_one", user)
    refute Dwar.enabled?("flag_two", user)

    join.update!(group: group_one)

    assert Dwar.enabled?("flag_two", user)
    assert Dwar.enabled?("flag_one", user)
  end

  test "creating a membership flips group-gated evaluation immediately" do
    flag = Dwar::Flag.create!(key: "mem_flag", state: "groups")
    group = Dwar::Group.create!(name: "g3")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "joiner")

    refute Dwar.enabled?("mem_flag", user)

    Dwar::GroupMembership.create!(group: group, actor: user)

    assert Dwar.enabled?("mem_flag", user)
  end

  test "destroying a membership flips group-gated evaluation immediately" do
    flag = Dwar::Flag.create!(key: "leave_flag", state: "groups")
    group = Dwar::Group.create!(name: "g4")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "leaver")
    membership = Dwar::GroupMembership.create!(group: group, actor: user)
    assert Dwar.enabled?("leave_flag", user)

    membership.destroy!

    refute Dwar.enabled?("leave_flag", user)
  end

  test "moving a membership to an untargeted group flips evaluation" do
    flag = Dwar::Flag.create!(key: "move_flag", state: "groups")
    targeted = Dwar::Group.create!(name: "targeted")
    untargeted = Dwar::Group.create!(name: "untargeted")
    Dwar::FlagGroup.create!(flag: flag, group: targeted)
    user = User.create!(name: "mover")
    membership = Dwar::GroupMembership.create!(group: targeted, actor: user)
    assert Dwar.enabled?("move_flag", user)

    membership.update!(group: untargeted)

    refute Dwar.enabled?("move_flag", user)
  end

  test "updating a group invalidates cached evaluations" do
    flag = Dwar::Flag.create!(key: "grp_upd", state: "groups")
    group = Dwar::Group.create!(name: "before")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "member")
    Dwar::GroupMembership.create!(group: group, actor: user)
    assert Dwar.enabled?("grp_upd", user)
    assert Dwar.enabled?("grp_upd", user)
    misses_before = Dwar::Cache.misses

    group.update!(name: "after")

    assert Dwar.enabled?("grp_upd", user)
    assert_equal misses_before + 1, Dwar::Cache.misses
  end

  test "destroying a group untargets its flags immediately" do
    flag = Dwar::Flag.create!(key: "grp_gone", state: "groups")
    group = Dwar::Group.create!(name: "gone")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "member")
    Dwar::GroupMembership.create!(group: group, actor: user)
    assert Dwar.enabled?("grp_gone", user)

    group.destroy!

    refute Dwar.enabled?("grp_gone", user)
  end

  test "groups_and_percentage flips on percentage change and membership loss" do
    flag = Dwar::Flag.create!(key: "gp_flip", state: "groups_and_percentage", percentage: 100)
    group = Dwar::Group.create!(name: "gp_group")
    Dwar::FlagGroup.create!(flag: flag, group: group)
    user = User.create!(name: "gp_member")
    membership = Dwar::GroupMembership.create!(group: group, actor: user)
    assert Dwar.enabled?("gp_flip", user)

    flag.update!(percentage: 0)
    refute Dwar.enabled?("gp_flip", user)

    flag.update!(percentage: 100)
    assert Dwar.enabled?("gp_flip", user)

    membership.destroy!
    refute Dwar.enabled?("gp_flip", user)
  end

  # -- transactional behavior -------------------------------------------------

  test "rolled back writes invalidate nothing" do
    flag = Dwar::Flag.create!(key: "rollback_flag", state: "disabled")
    refute Dwar.enabled?("rollback_flag")
    generation = Dwar::Cache.generation
    misses = Dwar::Cache.misses

    Dwar::Flag.transaction do
      flag.update!(state: "enabled")
      raise ActiveRecord::Rollback
    end

    assert flag.reload.disabled?
    assert_equal generation, Dwar::Cache.generation
    assert_equal misses, Dwar::Cache.misses
    refute Dwar.enabled?("rollback_flag")
    assert_equal 1, Dwar::Cache.hits
  end

  # -- cache toggle -----------------------------------------------------------

  test "disabling the cache re-evaluates every call" do
    flag = Dwar::Flag.create!(key: "toggle_flag", state: "enabled")
    assert Dwar.enabled?("toggle_flag")
    assert_equal 1, Dwar::Cache.misses

    Dwar.configure { |c| c.cache = false }
    # Bypass callbacks entirely: with the cache off the fresh row must be read
    # on every call regardless of invalidation.
    flag.update_column(:state, "disabled")

    refute Dwar.enabled?("toggle_flag")
    refute Dwar.enabled?("toggle_flag")
    assert_equal 1, Dwar::Cache.misses
    assert_equal 0, Dwar::Cache.hits
  end

  # -- thread safety ----------------------------------------------------------

  test "concurrent mixed reads and invalidations stay correct" do
    Dwar::Flag.create!(key: "thread_flag", state: "enabled")
    user = User.create!(name: "thread_user")
    assert Dwar.enabled?("thread_flag", user)
    generation_before = Dwar::Cache.generation

    results = Queue.new
    failures = Queue.new
    threads = 8.times.map do
      Thread.new do
        25.times do |i|
          results << Dwar.enabled?("thread_flag", user)
          Dwar::Cache.bump_flags(["thread_flag"]) if (i % 5).zero?
        end
      rescue => e
        failures << e
      end
    end
    threads.each { |t| t.join(15) }

    assert failures.empty?, "threads raised: #{failures.size} failure(s)"
    assert threads.none?(&:alive?), "threads deadlocked"

    drained = []
    drained << results.pop until results.empty?
    assert_equal 200, drained.size
    assert drained.all?(true), "every concurrent read must see the enabled flag"

    assert_operator Dwar::Cache.generation, :>, generation_before
    assert Dwar.enabled?("thread_flag", user)
  end

  # -- cached == uncached equivalence ------------------------------------------

  test "cached and uncached evaluation agree on pinned bucket boundaries" do
    # Pinned T05 tuples: rollout/User/1 -> 99, trial/User/1 -> 77,
    # rollout/User/2 -> 33 (strict-< edges).
    assert_equal 99, Dwar::Bucketing.bucket("rollout", "User", 1)
    assert_equal 77, Dwar::Bucketing.bucket("trial", "User", 1)
    assert_equal 33, Dwar::Bucketing.bucket("rollout", "User", 2)

    user_one = User.create!(id: 1, name: "user_one")
    user_two = User.create!(id: 2, name: "user_two")

    Dwar::Flag.create!(key: "rollout", state: "percentage", percentage: 99)
    Dwar::Flag.create!(key: "trial", state: "percentage", percentage: 78)
    Dwar::Flag.create!(key: "edge", state: "percentage", percentage: 33)

    refute Dwar.enabled?("rollout", user_one) # 99 < 99 is false
    assert Dwar.enabled?("trial", user_one) # 77 < 78 is true
    assert Dwar.enabled?("rollout", user_two) # 33 < 99 is true
    refute Dwar.enabled?("edge", user_two) # 33 < 33 is false

    assert_cached_matches_uncached("rollout", user_one)
    assert_cached_matches_uncached("trial", user_one)
    assert_cached_matches_uncached("rollout", user_two)
    assert_cached_matches_uncached("edge", user_two)
  end

  test "cached and uncached evaluation agree on 0% and 100%" do
    user = User.create!(name: "boundary_user")
    Dwar::Flag.create!(key: "pct_zero", state: "percentage", percentage: 0)
    Dwar::Flag.create!(key: "pct_hundred", state: "percentage", percentage: 100)

    refute Dwar.enabled?("pct_zero", user)
    assert Dwar.enabled?("pct_hundred", user)

    assert_cached_matches_uncached("pct_zero", user)
    assert_cached_matches_uncached("pct_hundred", user)
  end

  test "cached and uncached evaluation agree across all five states" do
    group = Dwar::Group.create!(name: "equiv")
    member = User.create!(name: "equiv_member")
    outsider = User.create!(name: "equiv_outsider")
    Dwar::GroupMembership.create!(group: group, actor: member)

    Dwar::Flag.create!(key: "st_disabled", state: "disabled")
    Dwar::Flag.create!(key: "st_enabled", state: "enabled")
    Dwar::Flag.create!(key: "st_pct", state: "percentage", percentage: 100)
    groups_flag = Dwar::Flag.create!(key: "st_groups", state: "groups")
    gp_flag = Dwar::Flag.create!(key: "st_gp", state: "groups_and_percentage", percentage: 100)
    Dwar::FlagGroup.create!(flag: groups_flag, group: group)
    Dwar::FlagGroup.create!(flag: gp_flag, group: group)

    %w[st_disabled st_enabled st_pct st_groups st_gp].each do |key|
      [member, outsider, nil].each do |actor|
        assert_cached_matches_uncached(key, actor, "#{key} with #{actor.inspect}")
      end
      # Both enabled? signatures.
      assert_cached_matches_uncached(key)
    end

    assert Dwar.enabled?("st_enabled", member)
    refute Dwar.enabled?("st_disabled", member)
    assert Dwar.enabled?("st_groups", member)
    refute Dwar.enabled?("st_groups", outsider)
    assert Dwar.enabled?("st_gp", member)
    refute Dwar.enabled?("st_gp", outsider)
  end

  test "nil actor, empty-id actor and unknown keys never raise and agree" do
    Dwar::Flag.create!(key: "pct_actorless", state: "percentage", percentage: 100)
    Dwar::Flag.create!(key: "grp_actorless", state: "groups")

    assert_nothing_raised { Dwar.enabled?(:nope) }
    assert_nothing_raised { Dwar.enabled?(:nope, User.new) }
    assert_nothing_raised { Dwar.enabled?("pct_actorless", nil) }
    assert_nothing_raised { Dwar.enabled?("pct_actorless", User.new) }
    assert_nothing_raised { Dwar.enabled?("grp_actorless", nil) }
    assert_nothing_raised { Dwar.enabled?("grp_actorless", User.new) }

    refute Dwar.enabled?(:nope)
    refute Dwar.enabled?(:nope, User.new)
    refute Dwar.enabled?("pct_actorless", nil)
    refute Dwar.enabled?("grp_actorless", User.new)

    assert_cached_matches_uncached(:nope)
    assert_cached_matches_uncached(:nope, User.new)
    assert_cached_matches_uncached("pct_actorless", nil)
    assert_cached_matches_uncached("pct_actorless", User.new)
    assert_cached_matches_uncached("grp_actorless", nil)
  end

  private

  def clean_database!
    Dwar::GroupMembership.delete_all
    Dwar::FlagGroup.delete_all
    Dwar::Flag.delete_all
    Dwar::Group.delete_all
    User.delete_all
  end

  def uncached_result(flag_key, actor = nil)
    Dwar.configure { |c| c.cache = false }
    Dwar.enabled?(flag_key, actor)
  ensure
    Dwar.reset_config
  end

  def assert_cached_matches_uncached(flag_key, actor = nil, message = nil)
    assert_equal uncached_result(flag_key, actor), Dwar.enabled?(flag_key, actor), message
  end
end
