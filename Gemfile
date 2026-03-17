source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.2.2"
gem "bootsnap", require: false
gem "dotenv-rails"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "rails", "~> 7.0.10"
gem "tzinfo-data", platforms: %i[mingw mswin x64_mingw jruby]

group :development, :test do
  gem "debug", platforms: %i[mri mingw x64_mingw]
end

group :development do
  gem "rubocop-rails"
  gem "rubocop-rspec"
end

gem "active_model_serializers", "~> 0.10.16"
gem "devise", "~> 5.0"

gem "actioncable"
gem "bcrypt", "~> 3.1"
gem "googleauth"
gem "httparty"
gem "jwt", "~> 2.8"
gem "kaminari", "~> 1.2"
gem "rack-attack"
gem "rack-cors", "~> 2.0"
gem "redis", "~> 4.0"
gem "rqrcode"
gem "sentry-rails"
gem "sentry-ruby"
gem "sidekiq", "~> 7.0"
# Gemfile
gem 'faker'

group :test do
  gem "action-cable-testing"
  gem "factory_bot_rails"
  gem "rspec-rails"
  gem "simplecov"
end
