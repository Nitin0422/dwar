# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

# Boot the mountable engine inside the committed dummy host app. The dummy's
# Bundler.require (config/application.rb) loads the dwar gem from the repo's
# own Gemfile/gemspec, so requiring the environment is all that is needed to
# exercise the engine as a real Rails application does.
require_relative "dummy/config/environment"

# The engine's migrations live in the gem root (db/migrate), outside the dummy
# app's own migration directory. The test boot's pending-migration check
# resolves Migrator.migrations_paths against the process working directory by
# default, so register the full set (engine first, then dummy) explicitly.
ActiveRecord::Migrator.migrations_paths = [
  File.expand_path("../db/migrate", __dir__),
  File.expand_path("dummy/db/migrate", __dir__)
]

# The test database is prepared explicitly by `rake dummy:test_db`
# (db:create db:migrate) before the suite runs. Disable Rails' automatic
# test-schema maintenance by design so the suite uses that migrated database
# as-is instead of purging and reloading it from the gitignored schema.rb.
ActiveRecord.maintain_test_schema = false

require "rails/test_help"
