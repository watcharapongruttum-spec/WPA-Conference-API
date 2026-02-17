require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module WPAConferenceApi
  class Application < Rails::Application
    config.load_defaults 7.0
    config.api_only = true

    # ==============================
    # TIME ZONE
    # ==============================
    config.time_zone = 'Asia/Bangkok'
    config.active_record.default_timezone = :local

    # ==============================
    # ACTIVE JOB
    # ==============================
    # Dev ใช้ async ได้
    config.active_job.queue_adapter = :async

    # ==============================
    # CACHE (จำเป็นสำหรับ Rack::Attack)
    # ==============================
    config.cache_store = :memory_store

    # ==============================
    # RACK ATTACK
    # ==============================
    require "rack/attack"
    config.middleware.use Rack::Attack
  end
end
