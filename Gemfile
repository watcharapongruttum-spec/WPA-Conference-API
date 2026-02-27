source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.2.2"
gem "rails", "~> 7.0.10"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "tzinfo-data", platforms: %i[ mingw mswin x64_mingw jruby ]
gem "bootsnap", require: false
gem "dotenv-rails"


group :development, :test do
  gem "debug", platforms: %i[ mri mingw x64_mingw ]
end

group :development do
end


gem "active_model_serializers", "~> 0.10.16"
gem "devise", "~> 5.0"

gem "rack-cors", "~> 2.0"
gem "kaminari", "~> 1.2"
gem "bcrypt", "~> 3.1"
gem 'actioncable'
gem 'redis', '~> 4.0'
gem 'rqrcode'
gem 'googleauth'
gem 'jwt', '~> 2.8'
gem 'rack-attack'
gem 'sidekiq', '~> 7.0'
gem 'sentry-ruby'
gem 'sentry-rails'
gem 'httparty'



group :test do
  gem 'rspec-rails'
  gem 'factory_bot_rails'
  gem 'action-cable-testing'
end