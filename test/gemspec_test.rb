# frozen_string_literal: true

require "test_helper"

# Guards the packaged file whitelist: the gem should ship its README and
# license, but never the test harness, docs, contributor guide, or the
# CI variant Gemfiles.
class GemspecTest < ActiveSupport::TestCase
  def setup
    gemspec = File.expand_path("../dwar.gemspec", __dir__)
    @spec = Gem::Specification.load(gemspec)
  end

  test "gemspec packages README and license" do
    refute_nil @spec
    assert_includes @spec.files, "README.md"
    assert_includes @spec.files, "LICENSE.txt"
  end

  test "gemspec excludes test and docs trees" do
    refute_nil @spec
    refute(@spec.files.any? { |path| path.start_with?("test/") })
    refute(@spec.files.any? { |path| path.start_with?("docs/") })
    refute_includes @spec.files, "CONTRIBUTING.md"
    refute(@spec.files.any? { |path| path.start_with?("gemfiles/") })
  end
end
