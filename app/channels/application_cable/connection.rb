module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_delegate

    def connect
      self.current_delegate = find_verified_delegate
      Rails.logger.info "✅ ActionCable connected delegate=#{current_delegate.id}"
    rescue StandardError => e
      Rails.logger.error "❌ ActionCable rejected: #{e.class} - #{e.message}"
      reject_unauthorized_connection
    end

    private

    def find_verified_delegate
      token = request.params[:token]
      payload = JwtDecoder.decode!(token)

      delegate = Delegate.find_by(id: payload["delegate_id"])
      raise "Delegate not found" unless delegate

      delegate
    rescue JWT::ExpiredSignature
      raise "Token expired"
    rescue JWT::DecodeError => e
      raise "JWT invalid: #{e.message}"
    end
  end
end
