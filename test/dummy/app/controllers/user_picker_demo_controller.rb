# frozen_string_literal: true

# Dev-only harness for manually exercising the T11 user picker end to end
# (type -> debounced search -> selectable results -> hidden id). Not part of
# the shipped gem: the dummy app exists to boot the engine in tests and for
# local verification. See app/views/user_picker_demo/index.html.erb for the
# manual verification steps.
class UserPickerDemoController < ApplicationController
  before_action :configure_dwar_for_demo

  # Serving javascript triggers Rails' cross-origin forgery protection;
  # exempt this static-file action (dev harness only).
  skip_forgery_protection only: [:user_picker_js]

  def index
  end

  # The engine ships no asset pipeline config, so the demo serves the
  # vanilla-JS picker file directly instead of relying on sprockets/propshaft.
  def user_picker_js
    send_file Dwar::Engine.root.join("app/assets/javascripts/dwar/user_picker.js"),
      type: "text/javascript", disposition: "inline"
  end

  private

  def configure_dwar_for_demo
    Dwar.configure do |c|
      c.authorization = ->(_controller) { true }
      c.user_finder = ->(query) {
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        User.where("name LIKE ?", pattern).order(:name).limit(50)
      }
      c.user_display = :name
    end
  end
end
