require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false

  config.public_file_server.enabled = true
  config.active_storage.service = :local

  config.log_level = :info
  config.log_tags = [:request_id]
  config.log_formatter = ::Logger::Formatter.new

  if ENV["RAILS_LOG_TO_STDOUT"].present?
    logger = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    config.logger = ActiveSupport::TaggedLogging.new(logger)
  end

  config.active_record.dump_schema_after_migration = false
  config.hosts.clear

  # SSL
  config.force_ssl = true

  # Action Cable
  config.action_cable.url = "wss://wpa-docker.onrender.com/cable"

  config.action_cable.allowed_request_origins = [
    "https://wpa-docker.onrender.com",
    /https:\/\/.*\.onrender\.com/
  ]
end
