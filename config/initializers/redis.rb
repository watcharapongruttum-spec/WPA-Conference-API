REDIS = Redis.new(
  url: ENV['REDIS_URL'] || 'redis://localhost:6379/1',
  reconnect_attempts: 3,
  timeout: 2
)
