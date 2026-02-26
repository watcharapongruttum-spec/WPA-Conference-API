# app/services/notification/broadcast_service.rb
class Notification::BroadcastService
  def self.call(notification)
    serialized = Api::V1::NotificationSerializer
                   .new(notification)
                   .serializable_hash

    # ActionCable → ส่งเสมอ (ไม่ว่า online/offline)
    NotificationChannel.broadcast_to(
      notification.delegate,
      type: 'new_notification',
      notification: serialized
    )

    if Chat::PresenceService.online?(notification.delegate_id)
      Rails.logger.info "📱 [BroadcastService] online → SKIP FCM (delegate=#{notification.delegate_id})"
    else
      Rails.logger.info "📵 [BroadcastService] offline → enqueue FCM (delegate=#{notification.delegate_id})"

      # ✅ delay 3 วิ กัน race condition ตอน WS กำลัง reconnect
      # ถ้า reconnect สำเร็จใน 3 วิ → online? = true → FCM job จะ skip
      NotificationDeliveryJob.set(wait: 3.seconds).perform_later(notification.id)
    end
  end
end