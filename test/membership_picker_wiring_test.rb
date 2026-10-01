# frozen_string_literal: true

require "test_helper"

# QA-04: host wiring for the membership picker JS must be documented where
# hosts actually look (README + install initializer). The memberships page
# fails visibly when the library is absent; these assertions pin the docs
# side of that contract so the <script> include cannot drift out silently.
class MembershipPickerWiringTest < ActiveSupport::TestCase
  ROOT = File.expand_path("..", __dir__)

  test "README documents the required picker script include" do
    readme = File.read(File.join(ROOT, "README.md"))

    assert_match(/Membership picker JS/, readme)
    assert_includes readme, "user_picker.js"
    assert_includes readme, "<script"
  end

  test "install initializer template documents the picker script include" do
    template = File.read(File.join(ROOT, "lib", "generators", "dwar", "install", "templates", "dwar.rb"))

    assert_includes template, "user_picker.js"
    assert_includes template, "<script"
  end
end
