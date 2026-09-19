# frozen_string_literal: true

require "test_helper"

class EngineTest < ActiveSupport::TestCase
  test "exposes an instantiable mountable Rails engine" do
    assert defined?(Dwar::Engine)
    assert_operator Dwar::Engine, :<, ::Rails::Engine
    assert_instance_of Dwar::Engine, Dwar::Engine.instance
  end

  test "engine namespace is isolated from the host application" do
    assert Dwar::Engine.isolated?

    # The engine ships Engine and VERSION. Assert presence rather than the
    # exact constant inventory: later features will legitimately add
    # constants (Configuration, Flag, Bucketing, ...). Isolation from the
    # host app is guaranteed below — were the engine to reopen host
    # constants, they would gain Dwar ancestry.
    assert_includes Dwar.constants, :Engine
    assert_includes Dwar.constants, :VERSION

    # Host constants defined by the dummy app must not have gained any Dwar
    # ancestry from loading the engine.
    [ApplicationController, ApplicationRecord, ApplicationHelper].each do |host_const|
      refute(
        host_const.ancestors.any? { |mod| mod.name.to_s.start_with?("Dwar::") },
        "expected #{host_const} to have no Dwar ancestry"
      )
    end

    # The engine routes are mounted at /dwar inside the host app and the
    # host default scope is untouched (no routes hijacked by the engine).
    # Compare against the "/dwar" prefix rather than the full path spec: the
    # spec string differs across Rails 7.1-8.x, but the mount point is stable.
    mounted = Rails.application.routes.routes.any? { |r| r.path.spec.to_s.start_with?("/dwar") }
    assert mounted, "expected the engine to be mounted at /dwar in the host app"

    defaults = Dwar::Engine.routes.default_scope
    assert_equal "dwar", defaults[:module].to_s
  end
end
