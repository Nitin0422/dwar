# frozen_string_literal: true

require "test_helper"
require "open3"

# Executable proof for the T11 vanilla-JS autocomplete (review H2): the asset
# must parse under node, and the dependency-free harness in
# test/javascript/user_picker_harness.cjs must prove the full
# debounce -> fetch -> render -> select -> hidden-field flow (plus the
# stale-response guard and the empty/failure states). Skipped when node is
# unavailable so plain Ruby environments stay green.
class UserPickerJsTest < ActiveSupport::TestCase
  ASSET = File.expand_path("../../app/assets/javascripts/dwar/user_picker.js", __dir__)
  HARNESS = File.expand_path("user_picker_harness.cjs", __dir__)

  def node_available?
    system("node --version", out: File::NULL, err: File::NULL)
  end

  test "picker javascript passes node syntax check" do
    skip "node not available" unless node_available?

    assert system("node", "--check", ASSET), "user_picker.js failed node --check"
  end

  test "picker harness proves debounce, fetch, render, select and stale guard" do
    skip "node not available" unless node_available?

    output, status = Open3.capture2e("node", HARNESS)

    assert status.success?, "harness failed:\n#{output}"
    assert_match(/HARNESS-OK/, output)
  end
end
