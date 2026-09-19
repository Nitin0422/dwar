# frozen_string_literal: true

require "test_helper"

# Pure-unit coverage of the configuration surface, in the same style as
# test/dwar_test.rb: plain Minitest, no fixtures or database records. setup
# and teardown reset the configuration so no state leaks across tests.
class ConfigurationTest < Minitest::Test
  def setup
    Dwar.reset_config
  end

  def teardown
    Dwar.reset_config
  end

  # AC 1, 2, 3 — defaults: frozen Dwar.config with PRD fallback values.
  def test_defaults_are_frozen_with_prd_fallbacks_before_any_configure_call
    config = Dwar.config

    assert_predicate config, :frozen?
    assert_nil config.user_finder
    assert_equal :to_s, config.user_display
    assert_equal "/dwar", config.admin_path
    assert_nil config.authorization
    assert_equal true, config.cache
    assert_nil config.audit_actor
  end

  def test_config_is_memoized_until_configure_replaces_it
    assert_same Dwar.config, Dwar.config

    Dwar.configure { |c| c.cache = false }

    refute_same Dwar::Configuration.default, Dwar.config
  end

  # AC 1 — configure yields the instance and Dwar.config returns it.
  def test_configure_yields_a_configuration_and_config_returns_it
    finder = ->(query) { [:alice, :bob] }
    authorization = ->(controller) { true }
    audit_actor = ->(controller) { "admin" }
    yielded = nil

    Dwar.configure do |c|
      yielded = c
      c.user_finder = finder
      c.user_display = :display_name
      c.admin_path = "/admin/dwar"
      c.authorization = authorization
      c.cache = false
      c.audit_actor = audit_actor
    end

    assert_instance_of Dwar::Configuration, yielded
    assert_same yielded, Dwar.config
    assert_same finder, Dwar.config.user_finder
    assert_equal :display_name, Dwar.config.user_display
    assert_equal "/admin/dwar", Dwar.config.admin_path
    assert_same authorization, Dwar.config.authorization
    assert_equal false, Dwar.config.cache
    assert_same audit_actor, Dwar.config.audit_actor
  end

  def test_partial_configure_keeps_defaults_for_unset_options
    finder = ->(query) { [:alice] }

    Dwar.configure { |c| c.user_finder = finder }

    assert_same finder, Dwar.config.user_finder
    assert_equal :to_s, Dwar.config.user_display
    assert_equal "/dwar", Dwar.config.admin_path
    assert_nil Dwar.config.authorization
    assert_equal true, Dwar.config.cache
    assert_nil Dwar.config.audit_actor
  end

  def test_configuration_is_isolated_between_configure_blocks
    Dwar.configure do |c|
      c.user_finder = ->(query) { [:alice] }
      c.user_display = :name
      c.admin_path = "/custom"
      c.authorization = ->(controller) { false }
      c.cache = false
      c.audit_actor = ->(controller) { "auditor" }
    end

    Dwar.configure { |c| c.cache = false }

    assert_nil Dwar.config.user_finder
    assert_equal :to_s, Dwar.config.user_display
    assert_equal "/dwar", Dwar.config.admin_path
    assert_nil Dwar.config.authorization
    assert_equal false, Dwar.config.cache
    assert_nil Dwar.config.audit_actor
  end

  def test_mutating_the_frozen_default_raises_frozen_error
    assert_raises(FrozenError) { Dwar.config.user_display = :name }
  end

  def test_configure_without_a_block_raises_argument_error
    assert_raises(ArgumentError) { Dwar.configure }
  end

  # AC 4 (first half) — an unset finder reads as nil and never raises.
  def test_unset_user_finder_reads_as_nil_without_raising
    assert_nil Dwar.config.user_finder
  end

  def test_user_finder_bang_returns_the_configured_finder
    finder = ->(query) { [:alice] }

    Dwar.configure { |c| c.user_finder = finder }

    assert_same finder, Dwar.config.user_finder!
    assert_equal [:alice], Dwar.config.user_finder!.call("al")
  end

  # AC 4 — user_finder! raises a descriptive ConfigurationError when unset.
  def test_user_finder_bang_raises_descriptive_configuration_error_when_unset
    error = assert_raises(Dwar::ConfigurationError) { Dwar.config.user_finder! }

    assert_match(/user_finder/, error.message)
    assert_match(/configure/, error.message)
  end

  def test_reset_config_restores_the_frozen_default
    Dwar.configure do |c|
      c.user_finder = ->(query) { [:alice] }
      c.cache = false
    end

    Dwar.reset_config

    assert_predicate Dwar.config, :frozen?
    assert_nil Dwar.config.user_finder
    assert_equal true, Dwar.config.cache
    assert_equal :to_s, Dwar.config.user_display
    assert_equal "/dwar", Dwar.config.admin_path
  end

  def test_callable_hooks_are_stored_and_invoke_with_a_dummy_argument
    Dwar.configure do |c|
      c.authorization = ->(controller) { true }
      c.audit_actor = ->(controller) { "admin" }
    end

    assert_equal true, Dwar.config.authorization.call(:dummy_controller)
    assert_equal "admin", Dwar.config.audit_actor.call(:dummy_controller)
  end
end
