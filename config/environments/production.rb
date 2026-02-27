require 'active_support/core_ext/integer/time'

Rails.application.configure do
  # Performance
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false

  config.public_file_server.enabled = true
  config.active_storage.service = :local

  # Logging
  config.log_level = :info
  config.log_tags = [:request_id]
  config.log_formatter = ::Logger::Formatter.new

  if ENV['RAILS_LOG_TO_STDOUT'].present?
    logger = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    config.logger = ActiveSupport::TaggedLogging.new(logger)
  end

  config.active_record.dump_schema_after_migration = false

  # Security
  config.force_ssl = true

  # =========================
  # IMPORTANT: APP HOST
  # =========================
  config.action_mailer.default_url_options = {
    host: ENV.fetch('APP_HOST'),
    protocol: 'https'
  }

  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true

  # =========================
  # Action Cable
  # =========================
  config.action_cable.url = ENV.fetch(
    'ACTION_CABLE_URL',
    "wss://#{ENV.fetch('APP_HOST')}/cable"
  )

  config.action_cable.allowed_request_origins = [
    %r{https?://.*}
  ]

  config.action_cable.disable_request_forgery_protection = true

  # Allow all hosts (Render internal)
  config.hosts.clear
end
