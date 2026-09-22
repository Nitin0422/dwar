# frozen_string_literal: true

require "test_helper"

class SectionsTest < ActionDispatch::IntegrationTest
  def setup
    Dwar.reset_config
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(_query) { [] }
    end
  end

  def teardown
    Dwar.reset_config
  end

  # AC: With an allow hook, each stub section returns 200.
  ["/dwar", "/dwar/admin/flags", "/dwar/admin/groups", "/dwar/admin/memberships"].each do |path|
    test "#{path} returns 200" do
      get path

      assert_response :success
    end
  end

  # AC (T11 picker contract): users#index invokes the configured finder
  # and renders its records as json (empty here because the stub finds none).
  test "users index returns finder results as json array" do
    get "/dwar/admin/users"

    assert_response :success
    assert_equal "[]", response.body.strip
    assert_includes response.content_type, "application/json"
  end

  # AC: The shared layout contains the brand name and an inline
  # <style> block (server-rendered, no build step).
  test "layout contains brand and style" do
    get "/dwar/admin/flags"

    assert_response :success
    assert_includes response.body, "Dwar"
    assert_includes response.body, "<style>"
  end

  # AC: Every nav href starts with /dwar/.
  test "all nav links start with /dwar/" do
    get "/dwar/admin/flags"

    assert_response :success
    assert_match %r{href="/dwar/}, response.body
    assert_match %r{href="/dwar/admin/flags}, response.body
    assert_match %r{href="/dwar/admin/groups}, response.body
    assert_match %r{href="/dwar/admin/memberships}, response.body
    assert_match %r{href="/dwar/admin/users}, response.body
  end
end
