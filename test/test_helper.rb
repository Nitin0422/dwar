# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

# Boot the mountable engine inside the committed dummy host app. The dummy's
# Bundler.require (config/application.rb) loads the dwar gem from the repo's
# own Gemfile/gemspec, so requiring the environment is all that is needed to
# exercise the engine as a real Rails application does.
require_relative "dummy/config/environment"
require "rails/test_help"
