# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "minitest", "~> 5.0"
gem "rake", "~> 13.0"
gem "standard", "~> 1.0"

# The dummy app (test/dummy) needs sqlite3 to boot and puma to serve
# `bin/rails server`. Both are development/test dependencies only and must
# NOT be added to the gemspec runtime dependencies.
group :development, :test do
  gem "sqlite3", "~> 2.0"
  gem "puma", "~> 6.0"
end
