# frozen_string_literal: true

require "test_helper"

class FlagTest < ActiveSupport::TestCase
  test "key presence is required" do
    flag = Dwar::Flag.new
    refute flag.valid?
    assert_includes flag.errors[:key], "can't be blank"
  end

  test "key must be unique" do
    Dwar::Flag.create!(key: "user.feature")
    duplicate = Dwar::Flag.new(key: "user.feature")
    refute duplicate.valid?
    assert_includes duplicate.errors[:key], "has already been taken"
  end

  test "key format accepts lowercase letters, digits, underscores, slashes, dots and dashes" do
    ["user.feature", "a/b", "a.b", "a-b", "a_b"].each do |key|
      assert Dwar::Flag.new(key: key).valid?, "expected #{key.inspect} to be a valid key"
    end
  end

  test "key format rejects spaces, uppercase, colons, question marks and blanks" do
    ["has space", "UPPER", "colon:key", "q?", ""].each do |key|
      refute Dwar::Flag.new(key: key).valid?, "expected #{key.inspect} to be an invalid key"
    end
  end

  test "state defaults to disabled" do
    flag = Dwar::Flag.create!(key: "user.feature")
    assert_equal "disabled", flag.state
    assert flag.disabled?
  end

  test "all five state values are assignable" do
    Dwar::Flag.states.each_key do |state|
      flag = Dwar::Flag.new(key: "user.#{state}")
      flag.state = state
      flag.percentage = 50 if %w[percentage groups_and_percentage].include?(state)
      assert flag.valid?, "expected state #{state.inspect} to be valid: #{flag.errors.full_messages}"
    end
  end

  test "unknown state values are rejected" do
    flag = Dwar::Flag.create!(key: "user.feature")
    flag.state = "bogus"
    refute flag.valid?
  end

  test "percentage defaults to zero" do
    flag = Dwar::Flag.create!(key: "user.feature")
    assert_equal 0, flag.percentage
  end

  test "percentage is range-checked when the state uses it" do
    %w[percentage groups_and_percentage].each do |state|
      flag = Dwar::Flag.new(key: "user.#{state}")
      flag.state = state

      flag.percentage = 0
      assert flag.valid?, "expected 0 to be accepted for state #{state}"

      flag.percentage = 100
      assert flag.valid?, "expected 100 to be accepted for state #{state}"

      flag.percentage = 101
      refute flag.valid?, "expected 101 to be rejected for state #{state}"

      flag.percentage = -1
      refute flag.valid?, "expected -1 to be rejected for state #{state}"

      flag.percentage = 1.5
      refute flag.valid?, "expected 1.5 to be rejected for state #{state}"
    end
  end

  test "percentage is ignored for non-percentage states" do
    %w[disabled enabled groups].each do |state|
      flag = Dwar::Flag.new(key: "user.#{state}")
      flag.state = state

      flag.percentage = 101
      assert flag.valid?, "expected out-of-range percentage to be ignored for state #{state}"

      flag.percentage = nil
      assert flag.valid?, "expected nil percentage to be ignored for state #{state}"
    end
  end

  test "flag exposes groups through the join model" do
    flag = Dwar::Flag.create!(key: "user.feature")
    group = Dwar::Group.create!(name: "beta")
    Dwar::FlagGroup.create!(flag: flag, group: group)

    assert_includes flag.reload.groups, group
  end
end
