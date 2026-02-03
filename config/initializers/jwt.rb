# JWT_SECRET = Rails.application.credentials.secret_key_base || 'development-secret-key-change-in-production'
# JWT_CONFIG = {
#   algorithm: 'HS256',
#   expiration_time: 24.hours.to_i,
#   issuer: 'wpa-conference-api'
# }.freeze







JWT_SECRET = ENV.fetch("JWT_SECRET")

JWT_CONFIG = {
  algorithm: 'HS256',
  expiration_time: 24.hours.to_i,
  issuer: 'wpa-conference-api'
}.freeze
