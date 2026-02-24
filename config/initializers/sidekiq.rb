Sidekiq.configure_server do |config|
  config.redis = { 
    url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/1'),
    timeout: 5,
    reconnect_attempts: 5,
    reconnect_delay: 1.0,
    reconnect_delay_max: 10.0
  }

  config.on(:startup) do
    KeepAliveJob.perform_later if Rails.env.production?
  end
end

Sidekiq.configure_client do |config|
  config.redis = { 
    url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/1'),
    timeout: 5,
    reconnect_attempts: 5
  }
end



