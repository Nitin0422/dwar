# frozen_string_literal: true

require "test_helper"

class DwarTest < Minitest::Test
  def test_version_is_a_semver_string
    # Strictly stronger than a non-empty String check: also rejects a
    # malformed version such as "v0.1" or "0.1".
    assert_match(/\A\d+\.\d+\.\d+\z/, Dwar::VERSION)
  end

  def test_dwar_is_defined
    assert defined?(Dwar)
  end
end
