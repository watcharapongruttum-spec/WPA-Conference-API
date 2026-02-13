class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_delegate

    ChatMessage.where(
      recipient_id: current_delegate.id,
      delivered_at: nil,
      deleted_at: nil
    ).update_all(delivered_at: Time.current)

    Rails.logger.info "✅ ChatChannel subscribed delegate=#{current_delegate.id}"
  end


  def unsubscribed
    Rails.logger.info "⚠️ ChatChannel unsubscribed delegate=#{current_delegate.id}"
  end

  # ================= ENTER ROOM =================
  def enter_room(data)
    data = safe_json(data)
    target_id = data["user_id"]
    user_id   = current_delegate.id

    # ---------- PRESENCE TTL ----------
    # ถ้า 60 วิ ไม่ ping จะหายเอง
    REDIS.setex("chat_open:#{user_id}:#{target_id}", 60, "1")

    # ---------- DEBOUNCE READ ----------
    lock_key = "read_lock:#{user_id}:#{target_id}"

    # ถ้าเพิ่งอ่านไปภายใน 2 วิ → ไม่ต้องยิงซ้ำ
    return if REDIS.get(lock_key)

    # lock 2 วินาที
    REDIS.setex(lock_key, 2, "1")

    MessageReadService.mark_room(user_id, target_id)
  end

  # ================= LEAVE ROOM =================
  def leave_room(data)
    data = safe_json(data)
    target_id = data["user_id"]

    REDIS.del("chat_open:#{current_delegate.id}:#{target_id}")
  end

  # ================= SEND MESSAGE =================
  def send_message(data)
    data = safe_json(data)

    message = ChatMessage.create!(
      sender: current_delegate,
      recipient_id: data['recipient_id'],
      content: data['content']
    )

    broadcast_new_message(message)
    create_notification(message)

  rescue => e
    handle_error(e)
  end

  # ================= READ MESSAGE =================
  def read_message(data)
    data = safe_json(data)
    msg = ChatMessage.find_by(id: data['message_id'])
    return unless msg && msg.recipient == current_delegate

    MessageReadService.mark_one(msg)
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

  # ---------- CHECK PRESENCE ----------
  def recipient_open_room?(message)
    key = "chat_open:#{message.recipient_id}:#{message.sender_id}"
    REDIS.get(key) == "1"
  end

  # ---------- NEW MESSAGE ----------
  def broadcast_new_message(message)
    # 🔥 AUTO SEEN
    if recipient_open_room?(message) && message.read_at.nil?
      MessageReadService.mark_one(message)
    end

    payload = {
      type: 'new_message',
      message: serializer(message)
    }

    ChatChannel.broadcast_to(message.sender, payload)
    ChatChannel.broadcast_to(message.recipient, payload)
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
