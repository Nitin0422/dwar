# frozen_string_literal: true

require "test_helper"

# Coverage for the T11 dev harness itself (review H2/M2): the dummy demo page
# renders the user picker partial contract, serves the picker javascript, and
# round-trips seeded users through the real picker endpoint.
class UserPickerDemoTest < ActionDispatch::IntegrationTest
  def setup
    Dwar.reset_config
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(query) {
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        User.where("name LIKE ?", pattern).order(:name).limit(50)
      }
      c.user_display = :name
    end
  end

  def teardown
    Dwar.reset_config
  end

  # The demo page renders the partial markup contract the JS wires into.
  test "demo page renders the picker contract" do
    get "/user_picker_demo"

    assert_response :success
    assert_includes response.body, "data-dwar-user-picker"
    assert_includes response.body, 'data-url="/dwar/admin/users.json"'
    assert_includes response.body, "data-dwar-user-picker-input"
    assert_includes response.body, "data-dwar-user-picker-hidden"
    assert_includes response.body, "data-dwar-user-picker-list"
    assert_includes response.body, "/user_picker_demo/user_picker.js"
  end

  # The demo serves the actual picker asset (no asset pipeline involved).
  test "demo serves the picker javascript" do
    get "/user_picker_demo/user_picker.js"

    assert_response :success
    assert_includes response.content_type, "javascript"
    assert_includes response.body, "DwarUserPicker"
  end

  # Seeded users round-trip through the real endpoint with display labels.
  test "demo picker endpoint returns seeded users" do
    User.create!(name: "Demo Alice")
    User.create!(name: "Demo Bob")

    get "/dwar/admin/users.json", params: {q: "Demo A"}

    assert_response :success
    assert_equal [{"id" => User.find_by(name: "Demo Alice").id, "label" => "Demo Alice"}],
      JSON.parse(response.body)
  end
end
