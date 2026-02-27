# JWT_CONFIG = {
#   secret: ENV.fetch("JWT_SECRET"),
#   algorithm: "HS256",
#   issuer: "your_app_name",
#   expiration_time: 24.hours
# }.freeze

# config/initializers/jwt.rb
JWT_CONFIG = {
  secret: ENV.fetch('JWT_SECRET'),
  algorithm: 'HS256',
  issuer: 'wpa-conference-api',
  expiration_time: 24.hours
}.freeze
