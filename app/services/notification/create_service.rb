class Notification::CreateService
  def self.call(message)
    lock_key = "notif_lock:#{message.id}"
    return if REDIS.get(lock_key)

    REDIS.setex(lock_key, 5, 1)

    recipient = message.recipient
    return unless recipient

    notification = ::Notification.create!(
      delegate: recipient,
      notification_type: 'new_message',
      notifiable: message
    )

    Notification::BroadcastService.call(notification)
  end
end
