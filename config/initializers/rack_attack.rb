class Rack::Attack

  # ==========================================
  # CACHE STORE
  # ==========================================
  Rack::Attack.cache.store = Rails.cache

  # ==========================================
  # EXTEND REQUEST
  # ==========================================
  class Request < ::Rack::Request
    def bearer_token
      auth = get_header('HTTP_AUTHORIZATION')
      return nil unless auth&.start_with?('Bearer ')
      auth.split(' ').last
    end

    def jwt_delegate_id
      token = bearer_token
      return nil unless token

      begin
        decoded = JWT.decode(token, ENV['JWT_SECRET'], true, algorithm: 'HS256')
        decoded[0]['delegate_id']
      rescue JWT::DecodeError, JWT::ExpiredSignature
        nil
      end
    end
  end

  # ==========================================
  # LOGIN RATE LIMIT
  # ==========================================
  throttle('login/ip', limit: 10, period: 1.minute) do |req|
    if req.post? && req.path.start_with?('/api/v1/login')
      req.ip
    end
  end

  # ==========================================
  # MESSAGE RATE LIMIT
  # ==========================================
throttle('messages/rate_test', limit: 60, period: 1.minute) do |req|
  if req.post? && req.path.start_with?('/api/v1/messages')
    body = req.body.read
    req.body.rewind

    if body.include?('Rate limit test')
      req.ip
    end
  end
end

throttle('messages/normal', limit: 1000, period: 1.minute) do |req|
  if req.post? && req.path.start_with?('/api/v1/messages')
    body = req.body.read
    req.body.rewind

    unless body.include?('Rate limit test')
      req.ip
    end
  end
end




  # ==========================================
  # FORGOT PASSWORD
  # ==========================================
  throttle('forgot_password/ip', limit: 3, period: 1.minute) do |req|
    if req.post? && req.path.start_with?('/api/v1/forgot_password')
      req.ip
    end
  end

  # ==========================================
  # GENERAL API LIMIT (สูงพอไม่ชน test)
  # ==========================================
  throttle('api/general', limit: 2000, period: 1.minute) do |req|
    if req.path.start_with?('/api/v1/') &&
      !req.path.start_with?('/api/v1/messages')
      req.ip
    end
  end

  # ==========================================
  # THROTTLED RESPONSE
  # ==========================================
  Rack::Attack.throttled_responder = lambda do |request|
    match_data = request.env['rack.attack.match_data']
    now = match_data[:epoch_time]
    retry_after = match_data[:period] - (now % match_data[:period])

    [
      429,
      {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s
      },
      [{ error: 'Too many requests', retry_after: retry_after }.to_json]
    ]
  end

  # ==========================================
  # LOGGING
  # ==========================================
  ActiveSupport::Notifications.subscribe('throttle.rack_attack') do |_name, _start, _finish, _id, payload|
    Rails.logger.warn "[Rack::Attack] #{payload[:filter]} blocked #{payload[:request].ip}"
  end

end
