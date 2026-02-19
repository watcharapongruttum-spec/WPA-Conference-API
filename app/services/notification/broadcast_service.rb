class Notification::BroadcastService
  def self.call(notification)
    serialized = Api::V1::NotificationSerializer
                    .new(notification)
                    .serializable_hash

    NotificationChannel.broadcast_to(
      notification.delegate,
      type: 'new_notification',
      notification: serialized
    )

        # FCM Push (เมื่อแอปปิดอยู่)
    NotificationDeliveryJob.perform_later(notification.id)

    
  end
end
