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

# The dummy:test_db rake step applies the migrations and dumps schema.rb, but
# db:migrate does not stamp ar_internal_metadata.schema_sha1 (only schema
# loads do). Without the stamp, maintain_test_schema! treats the freshly
# migrated schema as stale, purges the DB and reloads it from schema.rb —
# which records only the schema's single version and destroys the engine
# migration's version row, leaving it perpetually "pending". The schema file is
# current by construction here, so stamp the same SHA1 the check compares
# against.
schema_file = Rails.root.join("db", "schema.rb")
if schema_file.exist?
  ActiveRecord::Base.connection_pool.internal_metadata[:schema_sha1] =
    OpenSSL::Digest::SHA1.hexdigest(schema_file.read)
end

require "rails/test_help"
