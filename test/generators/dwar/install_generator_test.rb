# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/dwar/install/install_generator"
require "tmpdir"

# Exercises the dwar:install generator against a throwaway destination
# directory (Dir.mktmpdir), so no artifacts land in the repository.
class InstallGeneratorTest < Rails::Generators::TestCase
  tests Dwar::Generators::InstallGenerator

  setup do
    self.class.destination Dir.mktmpdir("dwar-install-generator")
    prepare_destination
  end

  teardown do
    root = self.class.destination_root
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  test "copies the migration and generates the initializer" do
    run_generator

    assert_migration "db/migrate/create_dwar_tables.rb"
    assert_file "config/initializers/dwar.rb"
  end

  test "copies every engine migration" do
    run_generator

    engine_migration_sources.each do |source|
      assert_migration "db/migrate/#{File.basename(source).sub(/\A\d+_/, "")}"
    end
  end

  test "generated initializer documents every configuration option" do
    run_generator

    assert_file "config/initializers/dwar.rb" do |initializer|
      assert_match(/Dwar\.configure/, initializer)
      %w[user_finder user_display admin_path authorization cache audit_actor].each do |option|
        assert_match(/#{option}/, initializer, "expected initializer to mention #{option}")
      end
      assert_match(/mount Dwar::Engine => "\/dwar"/, initializer)
    end
  end

  test "re-running does not duplicate migrations or clobber the initializer" do
    run_generator
    output = run_generator

    engine_migration_sources.each do |source|
      file_name = File.basename(source).sub(/\A\d+_/, "")
      copied = Dir[File.join(destination_root, "db", "migrate", "*_#{file_name}")]
      assert_equal 1, copied.length, "expected exactly one copy of #{file_name}"
    end

    assert_equal 1, Dir[File.join(destination_root, "config", "initializers", "dwar.rb")].length
    assert_match(/skip/i, output)
  end

  test "prints the mount line and next steps" do
    output = run_generator

    assert_match(/mount Dwar::Engine => "\/dwar"/, output)
    assert_match(/bin\/rails db:migrate/, output)
    assert_match(/config\/initializers\/dwar\.rb/, output)
  end

  test "leaves an existing initializer untouched" do
    FileUtils.mkdir_p(File.join(destination_root, "config", "initializers"))
    File.write(File.join(destination_root, "config", "initializers", "dwar.rb"), "# host edit\n")

    output = run_generator

    assert_file "config/initializers/dwar.rb", "# host edit\n"
    assert_match(/skip/i, output)
  end

  private

  def engine_migration_sources
    Dir[File.expand_path("../../../db/migrate/*.rb", __dir__)].sort
  end
end
