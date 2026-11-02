# frozen_string_literal: true

require "test_helper"

class AuthorizationTest < ActionDispatch::IntegrationTest
  def setup
    Dwar.reset_config
  end

  def teardown
    Dwar.reset_config
  end

  # AC: With no authorization hook configured, every admin route
  # denies access (fail closed) — 403 + clear deny message. Memberships are
  # nested under their group; auth runs before the group lookup, so no
  # group fixture is needed for the deny path.
  ["/dwar", "/dwar/admin/flags", "/dwar/admin/groups", "/dwar/admin/groups/1/memberships", "/dwar/admin/users"].each do |path|
    test "no hook configured: #{path} denies access with 403" do
      get path

      assert_response :forbidden
      assert_includes response.body, "Dwar admin is disabled"
      assert_includes response.body, "no authorization hook configured"
    end
  end

  # A literal non-callable value is treated the same as no hook: it cannot
  # authorize, so the "not configured" message is correct.
  test "non-callable authorization value uses the not-configured message" do
    Dwar.configure { |c| c.authorization = true }

    get "/dwar/admin/flags"

    assert_response :forbidden
    assert_includes response.body, "no authorization hook configured"
    refute_includes response.body, "access denied"
  end

  # AC: With a hook configured to return false, every admin route
  # denies access (fail closed).
  test "hook returning false denies all admin paths with 403" do
    Dwar.configure { |c| c.authorization = ->(_controller) { false } }

    ["/dwar", "/dwar/admin/flags", "/dwar/admin/groups", "/dwar/admin/groups/1/memberships", "/dwar/admin/users"].each do |path|
      get path

      assert_response :forbidden
      assert_includes response.body, "access denied"
      refute_includes response.body, "no authorization hook configured"
    end
  end

  # AC: nil and false are distinct failure modes: the unconfigured message
  # must never be shown for a configured hook that denied access.
  test "nil and false authorization hooks produce distinct deny messages" do
    get "/dwar/admin/flags"
    nil_body = response.body

    Dwar.configure { |c| c.authorization = ->(_controller) { false } }
    get "/dwar/admin/flags"
    false_body = response.body

    assert_response :forbidden
    assert_includes nil_body, "no authorization hook configured"
    assert_includes false_body, "access denied"
    refute_equal nil_body, false_body
  end

  # AC: With a hook configured to return true, admin routes are
  # reachable (200).
  test "hook returning true allows access to admin flags index" do
    Dwar.configure { |c| c.authorization = ->(_controller) { true } }

    get "/dwar/admin/flags"

    assert_response :success
  end

  # AC: The hook receives the controller as context and the caller
  # can inspect controller.params/request.
  test "hook receives controller as context" do
    captured = nil

    Dwar.configure do |c|
      c.authorization = ->(controller) {
        captured = controller
        true
      }
    end

    get "/dwar/admin/flags"

    assert_kind_of ActionController::Base, captured
    assert_respond_to captured, :params
    assert_respond_to captured, :request
    assert captured.params.is_a?(ActionController::Parameters)
    assert captured.request.is_a?(ActionDispatch::Request)
  end
end
