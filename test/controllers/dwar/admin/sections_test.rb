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
  ["/dwar", "/dwar/admin/flags", "/dwar/admin/groups"].each do |path|
    test "#{path} returns 200" do
      get path

      assert_response :success
    end
  end

  # AC: The nested per-group memberships screen returns 200.
  test "/dwar/admin/groups/:id/memberships returns 200" do
    group = Dwar::Group.create!(name: "beta")

    get "/dwar/admin/groups/#{group.id}/memberships"

    assert_response :success
  end

  # AC (T11 picker contract): users#index invokes the configured finder
  # with the query string and renders its records as a JSON array.
  test "users index returns finder results as json array" do
    received = :unset
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(query) {
        received = query
        []
      }
    end

    get "/dwar/admin/users.json", params: {q: "al"}

    assert_response :success
    assert_includes response.content_type, "application/json"
    assert_equal "al", received
    assert_equal [], JSON.parse(response.body)
  end

  # AC: The shared layout contains the brand name and an inline
  # <style> block (server-rendered, no build step).
  test "layout contains brand and style" do
    get "/dwar/admin/flags"

    assert_response :success
    assert_includes response.body, "Dwar"
    assert_includes response.body, "<style>"
  end

  # AC: Every nav href starts with /dwar/. Memberships live under their
  # group (no flat /dwar/admin/memberships nav entry); the groups index
  # links each row to its nested member list instead.
  test "all nav links start with /dwar/" do
    get "/dwar/admin/flags"

    assert_response :success
    assert_match %r{href="/dwar/}, response.body
    assert_match %r{href="/dwar/admin/flags}, response.body
    assert_match %r{href="/dwar/admin/groups}, response.body
    assert_match %r{href="/dwar/admin/users}, response.body
    assert_no_match %r{href="/dwar/admin/memberships}, response.body
  end

  test "groups index links each row to its nested member list" do
    Dwar::Group.create!(name: "beta")

    get "/dwar/admin/groups"

    assert_response :success
    assert_match %r{/dwar/admin/groups/\d+/memberships}, response.body
    assert_includes response.body, "Manage members"
  end
end
