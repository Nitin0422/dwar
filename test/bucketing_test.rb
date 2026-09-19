# frozen_string_literal: true

require "test_helper"

# Pure-unit coverage of Dwar::Bucketing, in the same style as
# test/configuration_test.rb: plain Minitest, no fixtures, no database, no
# dummy-app models (stdlib constants like String/Integer stand in for actor
# classes). The deterministic tests are the cross-process/version stability
# guard for the rollout scheme.
class BucketingTest < Minitest::Test
  # AC 1 — bucket always returns an Integer in 0..99.
  def test_bucket_returns_an_integer_in_0_to_99
    tuples = [
      [:rollout, "User", 0],
      [:rollout, "User", 1],
      [:rollout, "User", 42],
      [:trial, "Worker", 7],
      ["beta", "Account", 123_456],
      [:new, "String", "abc"],
      [:old, Integer, -5],
      ["groups", "Admin", "0"],
      [:foo_bar, "User", 99]
    ]

    tuples.each do |flag_key, actor_class, actor_id|
      bucket = Dwar::Bucketing.bucket(flag_key, actor_class, actor_id)

      assert_instance_of Integer, bucket
      assert_includes 0..99, bucket
    end
  end

  # AC 2 — identical inputs yield identical buckets.
  def test_bucket_is_deterministic_across_repeated_calls
    first = Dwar::Bucketing.bucket(:rollout, "User", 1)
    second = Dwar::Bucketing.bucket(:rollout, "User", 1)
    third = Dwar::Bucketing.bucket(:rollout, "User", 1)
    assert_equal first, second
    assert_equal first, third

    tuples = (1..200).map { |i| [:"flag_#{i}", "User", i] }
    first_pass = tuples.map { |flag_key, actor_class, actor_id| Dwar::Bucketing.bucket(flag_key, actor_class, actor_id) }
    second_pass = tuples.map { |flag_key, actor_class, actor_id| Dwar::Bucketing.bucket(flag_key, actor_class, actor_id) }
    assert_equal first_pass, second_pass
  end

  # AC 2 — the primary cross-process/version guard. These values were
  # generated independently of Dwar::Bucketing, directly against the scheme
  # string, e.g.:
  #
  #   ruby -rdigest -e 'puts Digest::SHA256.digest(ARGV[0])[0, 4].unpack1("N") % 100' "dwar-v1|rollout|User|1"
  #
  # They are scheme-dependent (SCHEME_PREFIX + tuple shape + digest formula):
  # regenerate ONLY if the scheme is intentionally changed.
  def test_bucket_matches_pinned_scheme_values
    [
      [["rollout", "User", 1], 99],
      [["trial", "User", 1], 77],
      [["rollout", "User", 2], 33],
      [["User", "rollout", 1], 64],
      [["rollout", "Admin", 1], 26],
      [["beta", "Account", 42], 4],
      [["rollout", "User", 7], 80],
      [["new", "String", 0], 92]
    ].each do |(flag_key, actor_class, actor_id), expected|
      assert_equal expected, Dwar::Bucketing.bucket(flag_key, actor_class, actor_id),
        "unexpected bucket for #{[flag_key, actor_class, actor_id].inspect}"
    end
  end

  # AC 3 — 10 000 actors spread over 3 flag keys. μ = 100 per bucket,
  # σ ≈ 10, so the 40..160 bounds are ~6σ — generous enough to never flake
  # while proving roughly uniform spread and that every bucket is reachable.
  def test_distribution_is_roughly_uniform_across_many_actors
    flag_keys = %i[rollout trial beta]
    counts = Array.new(100, 0)

    (1..10_000).each do |id|
      counts[Dwar::Bucketing.bucket(flag_keys[id % 3], "User", id)] += 1
    end

    counts.each_with_index do |count, bucket|
      assert_operator count, :>=, 40, "bucket #{bucket} under-represented (~100 expected)"
      assert_operator count, :<=, 160, "bucket #{bucket} over-represented (~100 expected)"
    end
  end

  # AC 4 — distinct actors/flags land across many buckets (aggregate bounds,
  # deliberately non-flaky).
  def test_distinct_inputs_are_generally_distinct
    actor_buckets = (1..500).map { |id| Dwar::Bucketing.bucket(:rollout, "User", id) }
    assert_operator actor_buckets.uniq.size, :>=, 50

    flag_buckets = (1..500).map { |i| Dwar::Bucketing.bucket("flag_#{i}", "User", 1) }
    assert_operator flag_buckets.uniq.size, :>=, 50
  end

  # AC 4 — the tuple is order-sensitive: both values are pinned above (99 and
  # 64), so the exact inequality is safe.
  def test_tuple_is_order_sensitive
    normal = Dwar::Bucketing.bucket("rollout", "User", 1)
    swapped = Dwar::Bucketing.bucket("User", "rollout", 1)

    refute_equal normal, swapped
  end

  # AC 5 — a class object and its name normalize identically.
  def test_class_and_string_class_normalize_identically
    assert_equal Dwar::Bucketing.bucket(:f, String, 1), Dwar::Bucketing.bucket(:f, "String", 1)
    assert_equal Dwar::Bucketing.bucket(:f, Integer, 1), Dwar::Bucketing.bucket(:f, "Integer", 1)
  end

  # AC 5 — integer and string actor ids normalize identically.
  def test_integer_and_string_ids_normalize_identically
    assert_equal Dwar::Bucketing.bucket(:f, "User", 42), Dwar::Bucketing.bucket(:f, "User", "42")
  end

  # AC 5 — symbol and string flag keys normalize identically.
  def test_symbol_flag_key_normalizes_like_string
    assert_equal Dwar::Bucketing.bucket(:trial, "User", 1), Dwar::Bucketing.bucket("trial", "User", 1)
  end

  def test_nil_actor_id_raises_argument_error
    error = assert_raises(ArgumentError) { Dwar::Bucketing.bucket(:rollout, "User", nil) }

    assert_match(/actor_id/, error.message)
    assert_match(/stable/, error.message)
  end

  def test_empty_actor_id_raises_argument_error
    error = assert_raises(ArgumentError) { Dwar::Bucketing.bucket(:rollout, "User", "") }

    assert_match(/actor_id/, error.message)
    assert_match(/stable/, error.message)
  end

  def test_nil_flag_key_raises_argument_error
    error = assert_raises(ArgumentError) { Dwar::Bucketing.bucket(nil, "User", 1) }

    assert_match(/flag_key/, error.message)
  end

  def test_empty_flag_key_raises_argument_error
    error = assert_raises(ArgumentError) { Dwar::Bucketing.bucket("", "User", 1) }

    assert_match(/flag_key/, error.message)
  end

  def test_non_string_or_symbol_flag_key_raises_argument_error
    error = assert_raises(ArgumentError) { Dwar::Bucketing.bucket(42, "User", 1) }

    assert_match(/flag_key/, error.message)
    assert_match(/String or Symbol/, error.message)
  end

  def test_empty_actor_class_raises_argument_error
    error = assert_raises(ArgumentError) { Dwar::Bucketing.bucket(:rollout, "", 1) }

    assert_match(/actor_class/, error.message)
  end
end
