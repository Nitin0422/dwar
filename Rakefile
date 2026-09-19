# frozen_string_literal: true

require "bundler/setup"

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

require "rake/testtask"

# The dummy app loaded above defines its own `test` task (Rails::TestUnit::Runner
# against the host app). Replace it with the engine's own test suite.
Rake::Task["test"].clear if Rake::Task.task_defined?("test")

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

# The dummy app's schema.rb is intentionally uncommitted (see .gitignore), so
# the test database must be built from migrations before the suite runs. The
# db:* tasks come from rails/tasks/engine.rake and delegate to the dummy app;
# running through the engine-root bin/rails defines ENGINE_ROOT, which is what
# registers the engine's own db/migrate on the host app.
desc "Prepare the dummy app's test database from migrations"
task "dummy:test_db" do
  sh "RAILS_ENV=test bin/rails db:create db:migrate"
end

task test: "dummy:test_db"

task default: :test
