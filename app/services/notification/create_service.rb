# app/services/notification/create_service.rb
class Notification::CreateService
  def self.call(message)
    recipient = message.recipient
    return unless recipient

    # ✅ FIX: ถ้า Redis down → skip lock แต่ยังส่ง notification ได้
    lock_key = "notif_lock:#{message.id}"
    begin
      acquired = REDIS.set(lock_key, 1, nx: true, ex: 5)
      return unless acquired
    rescue Redis::BaseError => e
      Rails.logger.warn "[CreateService] Redis unavailable, skipping lock: #{e.message}"
      # ถ้า Redis down → ยังส่ง notification ต่อได้ (อาจซ้ำในกรณีหายาก)
    end

    notification = ::Notification.create!(
      delegate: recipient,
      notification_type: "new_message",
      notifiable: message
    )

    Rails.cache.delete("dashboard:#{recipient.id}:v1")
    Notification::BroadcastService.call(notification)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[CreateService] Failed to create notification: #{e.message}"
  end
end
