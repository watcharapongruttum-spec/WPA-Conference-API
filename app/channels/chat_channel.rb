class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_delegate
    Rails.logger.info "✅ ChatChannel subscribed: delegate #{current_delegate.id}"
  end

  def unsubscribed
    Rails.logger.info "⚠️ ChatChannel unsubscribed: delegate #{current_delegate.id}"
  end

  def send_message(data)
    Rails.logger.info "📨 ChatChannel#send_message received: #{data.class}"

    data = JSON.parse(data) if data.is_a?(String)

    begin
      message = ChatMessage.create!(
        sender: current_delegate,
        recipient_id: data['recipient_id'],
        content: data['content']
      )

      recipient = message.recipient
      raise "Recipient not found" unless recipient

      serialized = Api::V1::ChatMessageSerializer
        .new(message)
        .serializable_hash[:data]

      # ส่งให้ผู้ส่ง
      ChatChannel.broadcast_to(
        current_delegate,
        type: 'new_message',
        message: serialized
      )

      # ส่งให้ผู้รับ
      ChatChannel.broadcast_to(
        recipient,
        type: 'new_message',
        message: serialized
      )

      # Notification
      notification = Notification.create!(
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

      Rails.logger.info "✅ Broadcast complete message=#{message.id}"

    rescue => e
      Rails.logger.error "❌ ChatChannel error: #{e.class} - #{e.message}"
      transmit(type: 'error', message: e.message)
    end
  end
end
