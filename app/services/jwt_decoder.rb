# app/services/jwt_decoder.rb
class JwtDecoder
  class << self
    def decode!(token)
      raise JWT::DecodeError, "Missing token" if token.blank?

      payload, = JWT.decode(
        token,
        JWT_CONFIG[:secret],
        true,
        {
          algorithm: JWT_CONFIG[:algorithm],
          iss: JWT_CONFIG[:issuer],
          verify_iss: true
        }
      )

      payload
    end
  end
end