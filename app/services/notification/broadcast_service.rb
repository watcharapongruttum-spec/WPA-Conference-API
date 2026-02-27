class Notification::BroadcastService
  # ✅ FCM เฉพาะ message และ admin เท่านั้น
  FCM_ALLOWED_TYPES = %w[new_message new_group_message admin_announce].freeze

  def self.call(notification)
    serialized = Api::V1::NotificationSerializer
                 .new(notification)
                 .serializable_hash

    # ActionCable ส่งทุก type เสมอ (in-app notification)
    NotificationChannel.broadcast_to(
      notification.delegate,
      type: "new_notification",
      notification: serialized
    )

    # FCM เฉพาะ type ที่กำหนดเท่านั้น
    unless FCM_ALLOWED_TYPES.include?(notification.notification_type)
      Rails.logger.info "🔕 [BroadcastService] skip FCM — type=#{notification.notification_type}"
      return
    end

    if Chat::PresenceService.online?(notification.delegate_id)
      Rails.logger.info "📱 [BroadcastService] online → SKIP FCM (delegate=#{notification.delegate_id})"
    else
      Rails.logger.info "📵 [BroadcastService] offline → enqueue FCM (delegate=#{notification.delegate_id})"
      NotificationDeliveryJob.set(wait: 3.seconds).perform_later(notification.id)
    end
  end
end
