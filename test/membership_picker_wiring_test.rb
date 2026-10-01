# frozen_string_literal: true

require "test_helper"
require "open3"

# QA-04: host wiring for the membership picker JS must be documented where
# hosts actually look (README + install initializer). The memberships page
# fails visibly when the library is absent; these assertions pin the docs
# side of that contract so the <script> include cannot drift out silently.
class MembershipPickerWiringTest < ActiveSupport::TestCase
  ROOT = File.expand_path("..", __dir__)
  HINT_HARNESS = File.expand_path("javascript/membership_picker_hint_harness.cjs", __dir__)

  test "README documents the required picker script include" do
    readme = File.read(File.join(ROOT, "README.md"))

    assert_match(/Membership picker JS/, readme)
    assert_includes readme, "user_picker.js"
    assert_includes readme, '<script src="/assets/dwar/user_picker.js">'
  end

  test "install initializer template documents the picker script include" do
    template = File.read(File.join(ROOT, "lib", "generators", "dwar", "install", "templates", "dwar.rb"))

    assert_includes template, "user_picker.js"
    assert_includes template, '<script src="/assets/dwar/user_picker.js">'
  end

  # QA-04 fix pass (H1/M1): executed proof for the memberships inline init.
  # The dependency-free node harness loads the actual inline <script> from
  # the view and proves hidden-by-default -> shown + console.warn on every
  # silent path (missing library/markup/endpoint/input, init returning no
  # handle, init throwing), the happy path staying silent, and the
  # never-throws posture. Skipped when node is unavailable.
  test "membership hint harness proves visible-hint behavior and never-throws" do
    skip "node not available" unless system("node --version", out: File::NULL, err: File::NULL)

    output, status = Open3.capture2e("node", HINT_HARNESS)

    assert status.success?, "hint harness failed:\n#{output}"
    assert_match(/HINT-HARNESS-OK/, output)
  end
end
