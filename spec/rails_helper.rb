# spec/rails_helper.rb
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'
require 'factory_bot_rails'
require 'action_cable/testing/rspec'

Dir[Rails.root.join('spec', 'support', '**', '*.rb')].sort.each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include ActionCable::TestHelper

  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # Clean Redis ก่อน/หลังแต่ละ test
  config.before(:each) do
    REDIS.flushdb if defined?(REDIS)
    Rails.cache.clear
  end
end