require "googleauth"
require "net/http"
require "json"

class FcmService
  SCOPE = "https://www.googleapis.com/auth/firebase.messaging".freeze

  def self.send_push(token:, title:, body:, data: {})
    return false if token.blank?

    debug_id = SecureRandom.hex(4)
    Time.current

    Rails.logger.warn "🚀 [FCM-#{debug_id}] START token=#{token.last(10)} title=#{title}"

    access_token = fetch_access_token
    return false unless access_token

    payload_hash = {
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
    }

    Rails.logger.warn "📦 [FCM-#{debug_id}] PAYLOAD=#{payload_hash}"

    uri = URI(fcm_endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{access_token}"
    request["Content-Type"] = "application/json"
    request.body = payload_hash.to_json

    duration = Benchmark.realtime do
      @response = http.request(request)
    end

    Rails.logger.warn "⏱ [FCM-#{debug_id}] duration=#{(duration * 1000).round}ms"

    if @response.code == "200"
      Rails.logger.warn "✅ [FCM-#{debug_id}] SUCCESS #{token.last(10)}"
      true
    else
      Rails.logger.error "❌ [FCM-#{debug_id}] ERROR #{@response.code} #{@response.body}"
      handle_invalid_token(token, @response.body)
      false
    end
  rescue StandardError => e
    Rails.logger.error "💥 [FCM-#{debug_id}] EXCEPTION #{e.class} #{e.message}"
    false
  end

  def self.fcm_endpoint
    "https://fcm.googleapis.com/v1/projects/#{ENV.fetch('FIREBASE_PROJECT_ID')}/messages:send"
  end

  # ✅ รองรับทั้ง Production (ENV JSON) และ Local (ไฟล์)
  def self.fetch_access_token
    Rails.cache.fetch("fcm_access_token", expires_in: 50.minutes) do
      json_io =
        if ENV["FIREBASE_CREDENTIALS_JSON"].present?
          StringIO.new(ENV["FIREBASE_CREDENTIALS_JSON"])
        else
          File.open(Rails.root.join(ENV.fetch("FIREBASE_CREDENTIALS_PATH")))
        end

      credentials = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: json_io,
        scope: SCOPE
      )

      credentials.fetch_access_token!["access_token"]
    end
  rescue StandardError => e
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
