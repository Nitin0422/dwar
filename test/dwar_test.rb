# frozen_string_literal: true

require "test_helper"

class DwarTest < Minitest::Test
  def test_version_is_a_non_empty_string
    assert_kind_of String, Dwar::VERSION
    refute_empty Dwar::VERSION
  end

  def test_dwar_is_defined
    assert defined?(Dwar)
  end
end
