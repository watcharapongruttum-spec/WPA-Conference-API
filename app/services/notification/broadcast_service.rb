# app/services/notification/broadcast_service.rb
class Notification::BroadcastService
  def self.call(notification)
    serialized = Api::V1::NotificationSerializer
                   .new(notification)
                   .serializable_hash

    # ActionCable → ส่งเสมอ
    NotificationChannel.broadcast_to(
      notification.delegate,
      type: 'new_notification',
      notification: serialized
    )

    unless Chat::PresenceService.online?(notification.delegate_id)
      Rails.logger.info "📵 [BroadcastService] msg offline → enqueue FCM (delegate=#{notification.delegate_id})"
      NotificationDeliveryJob.perform_later(notification.id)
    else
      Rails.logger.info "📱 [BroadcastService] msg online → SKIP FCM (delegate=#{notification.delegate_id})"
    end
  end
end