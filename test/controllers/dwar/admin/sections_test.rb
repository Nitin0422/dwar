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
    assert_match %r{href="/dwar/admin/audits}, response.body
    assert_no_match %r{href="/dwar/admin/users}, response.body
    assert_no_match %r{href="/dwar/admin/memberships}, response.body
  end

  test "groups index links each row to its nested member list" do
    Dwar::Group.create!(name: "beta")

    get "/dwar/admin/groups"

    assert_response :success
    assert_match %r{/dwar/admin/groups/\d+/memberships}, response.body
    assert_includes response.body, "Manage members"
  end

  # AC: UI-01 styles ship in the existing inline style block as design
  # tokens, so no asset pipeline or host setup is required. The compound
  # `.dwar-btn.dwar-btn--*` selectors are deliberate: they must outrank the
  # base `button[type="submit"]` rule so destructive/primary styling applies
  # at rest, not only on hover.
  test "redesigned flag form ships inline design tokens and picker styles" do
    get "/dwar/admin/flags/new"

    assert_response :success
    style = css_select("head style").first.text

    assert_includes style, "--dwar-accent: #4f46e5"
    assert_includes style, ".dwar-checkbox-list"
    assert_includes style, "overflow-y: auto"

    # WCAG 2.1 AA 1.4.11: #6b7280 is 4.83:1 vs #fff (4.63:1 vs #f9fafb).
    assert_includes style, "--dwar-border: #6b7280"

    # The search flex rule must follow the generic field-wrapper grid rule,
    # without an ID inside :not() raising its specificity.
    assert_includes style, "main #error_explanation { display: block; }"
    refute_includes style, ":not(#error_explanation)"
    field_rule = style.index("main form:not(.button_to) > div {")
    search_rule = style.index("main form.dwar-search > div {")
    refute_nil field_rule
    refute_nil search_rule
    assert_operator field_rule, :<, search_rule

    # Bare <table> tag: only the descendant alignment rule is allowed.
    assert_includes style, "main td { vertical-align: middle; }"

    # Pin the cascade contract, not just the presence of a substring: the
    # compound selectors carry two class tokens and therefore outrank the
    # base `input[type="submit"]` / `button[type="submit"]` rules. A
    # regression back to the single-class form must fail this test.
    assert_match(/main \.dwar-btn\.dwar-btn--primary\s*[,{]/, style)
    assert_match(/main \.dwar-btn\.dwar-btn--danger\s*\{/, style)
    refute_match(/main \.dwar-btn--primary\s*[,{]/, style)
    refute_match(/main \.dwar-btn--danger\s*[,{]/, style)
  end
end
