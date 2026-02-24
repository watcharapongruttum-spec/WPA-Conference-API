REDIS = Redis.new(
  url: ENV['REDIS_URL'] || 'redis://localhost:6379/1',
  reconnect_attempts: 5,
  reconnect_delay: 1.0,
  reconnect_delay_max: 10.0,
  timeout: 5,
  connect_timeout: 10
)