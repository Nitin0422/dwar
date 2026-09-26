# Set up gems listed in the Gemfile.
# Default to the engine root Gemfile so the dummy boots with the engine's
# dependencies (rails, dwar, sqlite3) regardless of cwd. An explicit
# BUNDLE_GEMFILE (e.g. a gemfiles/rails_*.gemfile matrix cell) is respected;
# a pointer at the dummy's own Gemfile is reset to the root so a stale
# BUNDLE_GEMFILE can never leave the dummy on a partial bundle.
root_gemfile = File.expand_path("../../../Gemfile", __dir__)
dummy_gemfile = File.expand_path("../Gemfile", __dir__)
current = ENV["BUNDLE_GEMFILE"]
if current.nil? || current.empty? || File.expand_path(current) == dummy_gemfile
  ENV["BUNDLE_GEMFILE"] = root_gemfile
end

require "bundler/setup" if File.exist?(ENV["BUNDLE_GEMFILE"])
$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)
