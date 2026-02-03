class ChatChannel < ApplicationCable::Channel
  def subscribed
    # ใช้ current_delegate (object) แทน current_delegate.id
    stream_for current_delegate
    logger.info "✅ ChatChannel subscribed: delegate #{current_delegate.id}"
  end

  def unsubscribed
    logger.info "⚠️ ChatChannel unsubscribed: delegate #{current_delegate.id}"
  end

  def send_message(data)
    logger.info "📨 ChatChannel#send_message received: #{data.class} - #{data.inspect}"
    
    # แยกวิเคราะห์ข้อมูลหากเป็นสตริง JSON
    data = JSON.parse(data) if data.is_a?(String)
    
    begin
      # สร้างข้อความ
      message = ChatMessage.create!(
        sender: current_delegate,
        recipient_id: data['recipient_id'],
        content: data['content']
      )
      
      logger.info "✅ Message created: #{message.id} from #{current_delegate.id} to #{message.recipient_id}"
      
      # ส่งข้อความไปยังผู้ส่ง (ใช้ object แทน ID)
      ChatChannel.broadcast_to(
        current_delegate,
        type: 'new_message',
        message: Api::V1::ChatMessageSerializer.new(message).serializable_hash
      )
      
      # ส่งข้อความไปยังผู้รับ (ใช้ object แทน ID)
      ChatChannel.broadcast_to(
        message.recipient,
        type: 'new_message',
        message: Api::V1::ChatMessageSerializer.new(message).serializable_hash
      )
      
      # สร้างการแจ้งเตือน
      notification = Notification.create!(
        delegate: message.recipient,
        notification_type: 'new_message',
        notifiable: message
      )
      
      # ส่งการแจ้งเตือนเรียลไทม์
      NotificationChannel.broadcast_to(
        message.recipient,
        type: 'new_notification',
        notification: {
          id: notification.id,
          type: 'new_message',
          created_at: notification.created_at,
          content: message.content.truncate(50),
          sender: {
            id: message.sender.id,
            name: message.sender.name,
            avatar_url: Api::V1::DelegateSerializer.new(message.sender).avatar_url
          }
        }
      )
      
      logger.info "✅ Broadcast complete for message #{message.id}"
      
    rescue => e
      logger.error "❌ Error in ChatChannel#send_message: #{e.class} - #{e.message}"
      logger.error e.backtrace.first(5).join("\n")
      transmit(type: 'error', message: e.message)
    end
  end
end