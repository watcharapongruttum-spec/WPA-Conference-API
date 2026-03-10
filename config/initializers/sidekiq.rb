redis_config = {
  url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/1'),
  timeout: 10,
  reconnect_attempts: 3
}

Sidekiq.configure_server do |config|
  config.redis = redis_config
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end
