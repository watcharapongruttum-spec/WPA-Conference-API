class Rack::Attack

  # ==========================================
  # CACHE STORE
  # ==========================================
  Rack::Attack.cache.store = Rails.cache

  # ==========================================
  # EXTEND REQUEST (JWT SAFE)
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
    req.ip if req.post? && req.path == '/api/v1/login'
  end

  # ==========================================
  # MESSAGE RATE LIMIT (Flexible)
  # ==========================================

  unless Rails.env.development? || Rails.env.test?

    # 🚀 Burst protection (กัน spam รัวใน 1 วินาที)
    throttle('messages/burst', limit: 20, period: 1.second) do |req|
      next unless req.post? && req.path.start_with?('/api/v1/messages')
      req.jwt_delegate_id || req.ip
    end

    # 🛡 Normal usage
    throttle('messages/normal', limit: 300, period: 1.minute) do |req|
      next unless req.post? && req.path.start_with?('/api/v1/messages')
      req.jwt_delegate_id || req.ip
    end

  end




  # ==========================================
  # DEVICE TOKEN (กัน spam update DB)
  # ==========================================
  throttle('device_token/user', limit: 10, period: 1.minute) do |req|
    if req.patch? && req.path == '/api/v1/device_token'
      req.jwt_delegate_id || req.ip
    end
  end

  # ==========================================
  # FORGOT PASSWORD
  # ==========================================
  throttle('forgot_password/ip', limit: 10, period: 1.minute) do |req|
    req.ip if req.post? && req.path == '/api/v1/forgot_password'
  end

  # ==========================================
  # GENERAL API LIMIT (ลดจาก 2000 → 300)
  # ==========================================
  throttle('api/general', limit: 300, period: 1.minute) do |req|
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







  throttle('reset_password/ip', limit: 5, period: 30.minute) do |req|
    req.ip if req.post? && req.path == '/api/v1/reset_password'
  end









end
