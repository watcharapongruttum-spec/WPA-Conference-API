module Notification
  class CreateService
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

      NotificationChannel.broadcast_to(
        recipient,
        type: 'new_notification',
        notification: {
          id: notification.id,
          type: 'new_message',
          created_at: notification.created_at,
          content: message.content.to_s[0, 50],
          sender: {
            id: message.sender.id,
            name: message.sender.name
          }
        }
      )
    end
  end
end
