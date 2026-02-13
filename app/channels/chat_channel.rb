class ChatChannel < ApplicationCable::Channel

  def subscribed
    stream_for current_delegate
    Chat::DeliveryService.mark_user_online(current_delegate.id)
    Chat::PresenceService.online(current_delegate.id)

    Rails.logger.info "✅ ChatChannel subscribed delegate=#{current_delegate.id}"
  end

  def unsubscribed
    Chat::PresenceService.offline(current_delegate.id)
    Rails.logger.info "⚠️ ChatChannel unsubscribed delegate=#{current_delegate.id}"
  end

  # ================= TYPING =================
  def typing(data)
    data = safe_json(data)
    other_id = data["target_id"]

    ChatChannel.broadcast_to(
      Delegate.find(other_id),
      {
        type: "typing",
        from: current_delegate.id
      }
    )
  end

  # ================= ENTER ROOM =================
  def enter_room(data)
    data = safe_json(data)
    target_id = data["user_id"]
    user_id   = current_delegate.id

    REDIS.setex("chat_open:#{user_id}:#{target_id}", 60, "1")

    lock_key = "read_lock:#{user_id}:#{target_id}"
    return if REDIS.get(lock_key)

    REDIS.setex(lock_key, 2, "1")


    Chat::ReadService.mark_room(user_id, target_id)

  end

  # ================= LEAVE ROOM =================
  def leave_room(data)
    data = safe_json(data)
    target_id = data["user_id"]

    REDIS.del("chat_open:#{current_delegate.id}:#{target_id}")
  end

  # ================= SEND MESSAGE (WS) =================
  def send_message(data)
    data = safe_json(data)

    message = Chat::SendMessageService.call(
      sender: current_delegate,
      recipient_id: data['recipient_id'],
      content: data['content']
    )

    create_notification(message)

  rescue => e
    handle_error(e)
  end













  # ================= READ MESSAGE =================
  def read_message(data)
    data = safe_json(data)
    msg = ChatMessage.find_by(id: data['message_id'])
    return unless msg && msg.recipient == current_delegate


    Chat::ReadService.mark_one(msg)

  end

  # =========================================================
  # PRIVATE
  # =========================================================
  private

  def safe_json(data)
    data.is_a?(String) ? JSON.parse(data) : data
  end

  def serializer(message)
    Api::V1::ChatMessageSerializer
      .new(message)
      .serializable_hash[:data]
  end

  def recipient_open_room?(message)
    key = "chat_open:#{message.recipient_id}:#{message.sender_id}"
    REDIS.get(key) == "1"
  end



  # ---------- NOTIFICATION ----------
  def create_notification(message)
    recipient = message.recipient
    return unless recipient

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
  end

  def handle_error(e)
    Rails.logger.error "❌ ChatChannel error: #{e.class} - #{e.message}"
    transmit(type: 'error', message: e.message)
  end
end
