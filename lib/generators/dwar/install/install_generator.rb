# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"
require "rails/generators/active_record/migration"

module Dwar
  module Generators
    # Installs Dwar into a host Rails application:
    #
    #   bin/rails generate dwar:install
    #
    # Copies every engine migration into the app (with a fresh timestamp) and
    # generates config/initializers/dwar.rb documenting the T04 configuration
    # surface as commented guidance.
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Copies Dwar migrations and generates a commented initializer"

      # Copy each engine migration into db/migrate under a fresh timestamp.
      # Already-copied migrations are skipped, so re-running never duplicates.
      def copy_migrations
        migration_dir = File.join(destination_root, "db", "migrate")

        migration_sources.each do |source|
          file_name = File.basename(source).sub(/\A\d+_/, "").sub(/\.rb\z/, "")
          if self.class.migration_exists?(migration_dir, file_name)
            say_status :skip, "db/migrate/#{file_name}.rb migration already exists"
          else
            timestamp = self.class.next_migration_number(migration_dir)
            create_file File.join("db", "migrate", "#{timestamp}_#{file_name}.rb"), File.read(source)
          end
        end
      end

      # Generate a commented initializer. An existing initializer is skipped
      # so re-runs never clobber host edits.
      def create_initializer
        destination = File.join(destination_root, "config", "initializers", "dwar.rb")
        if File.exist?(destination)
          say_status :skip, "config/initializers/dwar.rb already exists (leaving it untouched)"
        else
          copy_file "dwar.rb", "config/initializers/dwar.rb"
        end
      end

      # Print the recommended next steps, including the engine mount line.
      def print_next_steps
        say ""
        say "Dwar is installed. Next steps:"
        say ""
        say "  # Mount the engine in config/routes.rb:"
        say '  mount Dwar::Engine => "/dwar"'
        say ""
        say "  # Apply the copied migrations:"
        say "  bin/rails db:migrate"
        say ""
        say "  # Review and edit the generated initializer:"
        say "  config/initializers/dwar.rb"
      end

      private

      # The engine's own migration files, sorted for deterministic output.
      def migration_sources
        Dwar::Engine.root.join("db", "migrate").children
          .select { |path| path.extname == ".rb" }
          .sort
          .map(&:to_s)
      end
    end
  end
end
