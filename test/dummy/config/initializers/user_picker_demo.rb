# frozen_string_literal: true

# Dev-only Dwar configuration for the T11 user picker demo harness
# (UserPickerDemoController). Guarded to development so the test suite keeps
# full control of Dwar.config per test. Lets a freshly booted dummy server
# answer /dwar/admin/users.json even before /user_picker_demo is visited.
return unless Rails.env.development?

Dwar.configure do |c|
  c.authorization = ->(_controller) { true }
  c.user_finder = ->(query) {
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    User.where("name LIKE ?", pattern).order(:name).limit(50)
  }
  c.user_display = :name
end
