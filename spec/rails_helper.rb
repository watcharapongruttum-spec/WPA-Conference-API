# spec/rails_helper.rb
require "spec_helper"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "factory_bot_rails"
require "action_cable/testing/rspec"

# ✅ ถ้าใช้ Devise
require "devise"

# โหลด support files
Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # =========================
  # FactoryBot
  # =========================
  config.include FactoryBot::Syntax::Methods

  # =========================
  # Devise helpers
  # =========================
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::IntegrationHelpers, type: :request

  # =========================
  # ActionCable helpers
  # =========================
  config.include ActionCable::TestHelper

  # =========================
  # Database
  # =========================
  config.use_transactional_fixtures = true

  # =========================
  # RSpec behavior
  # =========================
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # =========================
  # Redis & Cache cleanup
  # =========================
  config.before(:each) do
    REDIS.flushdb if defined?(REDIS) && REDIS.respond_to?(:flushdb)

    Rails.cache.clear
  end
end
