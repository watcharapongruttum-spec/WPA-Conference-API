# app/services/fcm_service.rb
require 'googleauth'
require 'net/http'
require 'json'

class FcmService
  SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'

  def self.send_push(token:, title:, body:, data: {})
    return false if token.blank?

    access_token = fetch_access_token
    return false unless access_token

    payload = {
      message: {
        token: token,
        notification: { title: title, body: body },
        android: { priority: "high" },
        apns: { headers: { "apns-priority": "10" } },
        data: data.transform_values(&:to_s)
      }
    }.to_json

    uri = URI(fcm_endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)  # ✅ แก้จาก uri.path
    request['Authorization'] = "Bearer #{access_token}"
    request['Content-Type'] = 'application/json'
    request.body = payload

    response = http.request(request)

    if response.code == '200'
      Rails.logger.info "✅ FCM Sent successfully to #{token.last(10)}"
      true
    else
      Rails.logger.error "❌ FCM Error #{response.code}: #{response.body}"
      handle_invalid_token(token, response.body)
      false
    end
  rescue => e
    Rails.logger.error "❌ FCM Exception: #{e.message}"
    false
  end

  private

  def self.fcm_endpoint  # ✅ แก้จาก constant
    "https://fcm.googleapis.com/v1/projects/#{ENV.fetch('FIREBASE_PROJECT_ID')}/messages:send"
  end

  def self.fetch_access_token
    Rails.cache.fetch("fcm_access_token", expires_in: 50.minutes) do  # ✅ cache token
      credentials = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: File.open(Rails.root.join(ENV.fetch('FIREBASE_CREDENTIALS_PATH'))),
        scope: SCOPE
      )
      credentials.fetch_access_token!['access_token']
    end
  rescue => e
    Rails.logger.error "❌ FCM Auth Error: #{e.message}"
    nil
  end

  def self.handle_invalid_token(token, body)  # ✅ auto cleanup
    return unless body.include?("UNREGISTERED")
    Delegate.find_by(device_token: token)&.update(device_token: nil)
    Rails.logger.warn "🗑 Removed invalid FCM token"
  end
end