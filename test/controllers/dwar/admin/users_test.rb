# frozen_string_literal: true

require "test_helper"

class UsersTest < ActionDispatch::IntegrationTest
  FakeRecord = Struct.new(:id, :name) do
    def to_s
      "fake-#{id}-#{name}"
    end

    def display_name
      "DN:#{name}"
    end
  end

  def setup
    Dwar.reset_config
  end

  def teardown
    Dwar.reset_config
  end

  def allow_admin!
    Dwar.configure { |c| c.authorization = ->(_controller) { true } }
  end

  # Captures Rails.logger output for the duration of the block.
  def capture_log
    io = StringIO.new
    old_logger = Rails.logger
    Rails.logger = Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = old_logger
  end

  # Happy path: finder receives the query string and records map to id/label.
  test "index invokes finder with q and returns id/label json" do
    received = nil
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(query) {
        received = query
        [FakeRecord.new(1, "alice")]
      }
    end

    get "/dwar/admin/users.json", params: {q: "al"}

    assert_response :success
    assert_includes response.content_type, "application/json"
    assert_equal "al", received
    assert_equal [{"id" => 1, "label" => "fake-1-alice"}], JSON.parse(response.body)
  end

  # Label honors a custom Symbol user_display.
  test "index honors symbol user_display" do
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(_query) { [FakeRecord.new(2, "bob")] }
      c.user_display = :display_name
    end

    get "/dwar/admin/users.json", params: {q: "bo"}

    assert_response :success
    assert_equal [{"id" => 2, "label" => "DN:bob"}], JSON.parse(response.body)
  end

  # Label honors a callable user_display.
  test "index honors callable user_display" do
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(_query) { [FakeRecord.new(3, "carol")] }
      c.user_display = ->(record) { "CALL:#{record.name.upcase}" }
    end

    get "/dwar/admin/users.json", params: {q: "ca"}

    assert_response :success
    assert_equal [{"id" => 3, "label" => "CALL:CAROL"}], JSON.parse(response.body)
  end

  # Missing finder: safe 503 JSON error, never 500 or a stack trace.
  test "index without user_finder returns 503 json error" do
    allow_admin!

    get "/dwar/admin/users.json", params: {q: "al"}

    assert_response :service_unavailable
    assert_includes response.content_type, "application/json"
    assert_includes response.body, "user_finder not configured"
    assert_equal({"error" => "user_finder not configured"}, JSON.parse(response.body))
  end

  # Raising finder: safe 200 [] fallback, never 500 — JSON content-type,
  # empty array body, and a logged warning with no leak.
  test "index with raising finder returns empty array" do
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(_query) { raise "boom" }
    end

    logged = capture_log do
      get "/dwar/admin/users.json", params: {q: "al"}
    end

    assert_response :success
    assert_includes response.content_type, "application/json"
    assert_equal [], JSON.parse(response.body)
    assert_match(/user_finder failed/, logged)
    assert_not_includes logged, "boom"
  end

  # Edge: missing q normalizes to "" and still invokes the finder.
  test "index without q passes empty string to finder" do
    received = :unset
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(query) {
        received = query
        []
      }
    end

    get "/dwar/admin/users.json"

    assert_response :success
    assert_equal "", received
    assert_equal [], JSON.parse(response.body)
  end

  # Edge: explicit empty q behaves the same.
  test "index with empty q passes empty string to finder" do
    received = :unset
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(query) {
        received = query
        []
      }
    end

    get "/dwar/admin/users.json", params: {q: ""}

    assert_response :success
    assert_equal "", received
    assert_equal [], JSON.parse(response.body)
  end

  # Edge: finder returning [] renders [].
  test "index with empty finder results returns empty array" do
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(_query) { [] }
    end

    get "/dwar/admin/users.json", params: {q: "zzz"}

    assert_response :success
    assert_equal [], JSON.parse(response.body)
  end

  # Edge: non-integer ids pass through untouched.
  test "index preserves odd id types" do
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(_query) { [FakeRecord.new("uuid-123", "zed")] }
    end

    get "/dwar/admin/users.json", params: {q: "z"}

    assert_response :success
    assert_equal [{"id" => "uuid-123", "label" => "fake-uuid-123-zed"}], JSON.parse(response.body)
  end

  # Edge: records without id are skipped, never a 500.
  test "index skips records without id" do
    bad = Struct.new(:name).new("noid")
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(_query) { [bad, FakeRecord.new(9, "ok")] }
    end

    get "/dwar/admin/users.json", params: {q: "o"}

    assert_response :success
    assert_equal [{"id" => 9, "label" => "fake-9-ok"}], JSON.parse(response.body)
  end

  # Edge: records with a nil id are skipped with a warning, never {id: null}.
  test "index skips records with nil id" do
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(_query) { [FakeRecord.new(nil, "ghost"), FakeRecord.new(10, "real")] }
    end

    logged = capture_log do
      get "/dwar/admin/users.json", params: {q: "r"}
    end

    assert_response :success
    assert_equal [{"id" => 10, "label" => "fake-10-real"}], JSON.parse(response.body)
    assert_match(/nil id/, logged)
  end

  # H1 regression: a single record with a raising #id or #to_s must not wipe
  # the whole result set — bad records are skipped, good ones are kept.
  test "index keeps good records when one record raises on id or to_s" do
    explosive_id = FakeRecord.new(11, "bad-id")
    explosive_id.define_singleton_method(:id) { raise "id exploded" }
    toxic_label = FakeRecord.new(12, "bad-label")
    toxic_label.define_singleton_method(:to_s) { raise "to_s exploded" }
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(_query) { [FakeRecord.new(13, "good"), explosive_id, toxic_label] }
    end

    logged = capture_log do
      get "/dwar/admin/users.json", params: {q: "g"}
    end

    assert_response :success
    assert_includes response.content_type, "application/json"
    assert_equal [{"id" => 13, "label" => "fake-13-good"}], JSON.parse(response.body)
    assert_match(/record failed/, logged)
  end

  # Edge: failing label computation falls back to to_s, never a 500.
  test "index falls back to to_s when user_display fails" do
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(_query) { [FakeRecord.new(4, "dave")] }
      c.user_display = :nonexistent_method_xyz
    end

    get "/dwar/admin/users.json", params: {q: "da"}

    assert_response :success
    assert_equal [{"id" => 4, "label" => "fake-4-dave"}], JSON.parse(response.body)
  end

  # Guard: oversized finder results are capped so one keystroke never
  # serializes an unbounded JSON body.
  test "index caps results at the picker limit" do
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(_query) { (1..60).map { |i| FakeRecord.new(i, "user#{i}") } }
    end

    get "/dwar/admin/users.json", params: {q: "user"}

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal Dwar::Admin::UsersController::PICKER_RESULT_LIMIT, body.size
    assert_equal 1, body.first["id"]
  end

  # Auth regression: fail closed without a hook, even for the JSON picker.
  test "index without authorization hook denies picker with 403" do
    get "/dwar/admin/users.json", params: {q: "al"}

    assert_response :forbidden
    assert_includes response.body, "Dwar admin is disabled"
  end
end
