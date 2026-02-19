# app/services/fcm_service.rb
require 'googleauth'
require 'net/http'
require 'json'

class FcmService
  FCM_ENDPOINT = "https://fcm.googleapis.com/v1/projects/#{ENV['FIREBASE_PROJECT_ID']}/messages:send"
  SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'

  def self.send_push(token:, title:, body:, data: {})
    return false if token.blank?

    access_token = fetch_access_token
    return false unless access_token

    payload = {
      message: {
        token: token,
        notification: { title: title, body: body },
        data: data.transform_values(&:to_s)
      }
    }.to_json

    uri = URI(FCM_ENDPOINT)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request['Authorization'] = "Bearer #{access_token}"
    request['Content-Type'] = 'application/json'
    request.body = payload

    response = http.request(request)

    if response.code == '200'
      Rails.logger.info "✅ FCM Sent successfully"
      true
    else
      Rails.logger.error "❌ FCM Error #{response.code}: #{response.body}"
      false
    end
  rescue => e
    Rails.logger.error "❌ FCM Exception: #{e.message}"
    false
  end

  private

  def self.fetch_access_token
    credentials = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(ENV['FIREBASE_CREDENTIALS_PATH']),
      scope: SCOPE
    )
    credentials.fetch_access_token!['access_token']
  rescue => e
    Rails.logger.error "❌ FCM Auth Error: #{e.message}"
    nil
  end
end
