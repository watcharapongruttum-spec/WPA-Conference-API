Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/1') }

    # เริ่ม keep-alive ตอน server boot (production เท่านั้น)
  config.on(:startup) do
    KeepAliveJob.perform_later if Rails.env.production?
  end

  
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/1') }
end