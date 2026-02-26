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
        notification: {
          title: title,
          body: body
        },
        android: {
          priority: "high",
          notification: {
            sound: "default",
            click_action: "FLUTTER_NOTIFICATION_CLICK"
          }
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1
            }
          }
        },
        data: data.transform_values(&:to_s)
      }
    }.to_json

    uri = URI(fcm_endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
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

  def self.fcm_endpoint
    "https://fcm.googleapis.com/v1/projects/#{ENV.fetch('FIREBASE_PROJECT_ID')}/messages:send"
  end

  # ✅ รองรับทั้ง Production (ENV JSON) และ Local (ไฟล์)
  def self.fetch_access_token
    Rails.cache.fetch("fcm_access_token", expires_in: 50.minutes) do
      json_io =
        if ENV['FIREBASE_CREDENTIALS_JSON'].present?
          StringIO.new(ENV['FIREBASE_CREDENTIALS_JSON'])
        else
          File.open(Rails.root.join(ENV.fetch('FIREBASE_CREDENTIALS_PATH')))
        end

      credentials = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: json_io,
        scope: SCOPE
      )

      credentials.fetch_access_token!['access_token']
    end
  rescue => e
    Rails.logger.error "❌ FCM Auth Error: #{e.message}"
    nil
  end

  # ลบ token ที่ invalid
  def self.handle_invalid_token(token, body)
    parsed = JSON.parse(body)
    error_code = parsed.dig("error", "details")
                       &.find { |d| d["errorCode"].present? }
                       &.dig("errorCode")
    status  = parsed.dig("error", "status")
    message = parsed.dig("error", "message").to_s

    invalid = error_code == "UNREGISTERED" ||
              status == "NOT_FOUND" ||
              message.include?("not a valid FCM registration token")

    return unless invalid

    count = Delegate.where(device_token: token).update_all(device_token: nil)
    Rails.logger.warn "🗑 Removed invalid FCM token from #{count} delegate(s)"
  rescue JSON::ParserError
    Rails.logger.error "❌ FCM: Could not parse error body"
  end
end