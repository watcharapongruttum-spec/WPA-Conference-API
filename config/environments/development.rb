require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Reload code on change
  config.cache_classes = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  # ===============================
  # IMPORTANT: ENABLE CACHING FOR RACK::ATTACK
  # ===============================
  config.action_controller.perform_caching = true
  config.cache_store = :memory_store

  # Active Storage
  config.active_storage.service = :local

  # Mailer
  config.action_mailer.perform_caching = false
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true

  config.action_mailer.smtp_settings = {
    address: "smtp.gmail.com",
    port: 587,
    domain: "gmail.com",
    user_name: ENV["MAIL_USER"],
    password: ENV["MAIL_PASS"],
    authentication: "plain",
    enable_starttls_auto: true
  }

  # Deprecation
  config.active_support.deprecation = :log
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []

  # Migration check
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true

  # ===============================
  # Action Cable
  # ===============================
  config.action_cable.mount_path = "/cable"

  config.action_cable.url = ENV.fetch(
    "ACTION_CABLE_URL",
    "ws://localhost:3000/cable"
  )

  config.action_cable.disable_request_forgery_protection = true

  config.action_cable.allowed_request_origins = [
    'http://localhost:3000',
    'http://127.0.0.1:3000',
    'http://localhost:5173',
    'http://127.0.0.1:5173',
    nil
  ]
end
