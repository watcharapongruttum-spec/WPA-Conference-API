# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_delegate

    def connect
      self.current_delegate = find_verified_delegate
      logger.info "✅ ActionCable connected delegate=#{current_delegate.id}"
    rescue => e
      logger.error "❌ ActionCable rejected: #{e.message}"
      reject_unauthorized_connection
    end

    private

    def find_verified_delegate
      token = request.params[:token]
      raise "Missing token" if token.blank?

      payload, = JWT.decode(
        token,
        JWT_SECRET,
        true,
        {
          algorithm: JWT_CONFIG[:algorithm],
          iss: JWT_CONFIG[:issuer],
          verify_iss: true
        }
      )

      Delegate.find(payload["delegate_id"])
    rescue JWT::ExpiredSignature
      raise "Token expired"
    rescue JWT::DecodeError => e
      raise "JWT invalid: #{e.message}"
    end
  end
end
