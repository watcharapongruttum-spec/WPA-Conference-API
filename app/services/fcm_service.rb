# app/services/fcm_service.rb
require 'firebase/admin'

class FcmService
  def self.send_push(token:, title:, body:,  {})
    return if token.blank?

    # Initialize Firebase
    Firebase.admin.configure do |config|
      config.project_id = ENV['FIREBASE_PROJECT_ID']
      config.credentials = ENV['FIREBASE_CREDENTIALS_PATH']
    end

    begin
      message = {
        token: token,
        notification: {
          title: title,
          body: body
        },
         data.transform_values(&:to_s) # FCM รับ data เป็น string เท่านั้น
      }

      response = Firebase::Admin::Messaging.send_message(message)
      Rails.logger.info "✅ FCM Sent: #{response.name}"
      true
    rescue => e
      Rails.logger.error "❌ FCM Error: #{e.message}"
      false
    end
  end
end