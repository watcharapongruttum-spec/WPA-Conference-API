class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_delegate
    Rails.logger.info "✅ ChatChannel subscribed delegate=#{current_delegate.id}"
  end

  def unsubscribed
    Rails.logger.info "⚠️ ChatChannel unsubscribed delegate=#{current_delegate.id}"
  end

  # ================= SEND =================
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

  # ================= READ =================
  def read_message(data)
    data = safe_json(data)
    msg = ChatMessage.find_by(id: data['message_id'])
    return unless msg && msg.recipient == current_delegate

    msg.update(read_at: Time.current)

    ChatChannel.broadcast_to(
      msg.sender,
      type: 'message_read',
      message_id: msg.id,
      read_at: msg.read_at
    )
  end

  # ================= EDIT =================
  def edit_message(data)
    data = safe_json(data)
    msg = ChatMessage.find_by(id: data['message_id'])
    return unless msg && msg.sender == current_delegate

    msg.update!(
      content: data['content'],
      edited_at: Time.current
    )

    broadcast_update(msg)
  end

  # ================= DELETE =================
  def delete_message(data)
    data = safe_json(data)
    msg = ChatMessage.find_by(id: data['message_id'])
    return unless msg && msg.sender == current_delegate

    msg.update!(
      deleted_at: Time.current,
      is_deleted: true
    )

    broadcast_delete(msg)
  end

  # ================= ENTER ROOM =================
  def enter_room(data)
    data = safe_json(data)
    target_id = data["user_id"]

    REDIS.set("chat_open:#{current_delegate.id}:#{target_id}", true)

    mark_conversation_as_read(target_id)
  end

  # ================= LEAVE ROOM =================
  def leave_room(data)
    data = safe_json(data)
    other_user_id = data["user_id"]

    REDIS.del("chat_open:#{current_delegate.id}:#{other_user_id}")
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
    REDIS.get(key)
  end

  # ---------- NEW MESSAGE ----------
  def broadcast_new_message(message)

    # 🔥 AUTO SEEN IF OPEN ROOM
    if recipient_open_room?(message) && message.read_at.nil?
      now = Time.current
      message.update_column(:read_at, now)

      ChatChannel.broadcast_to(
        message.sender,
        type: 'message_read',
        message_id: message.id,
        read_at: now
      )
    end

    payload = {
      type: 'new_message',
      message: serializer(message)
    }

    ChatChannel.broadcast_to(message.sender, payload)
    ChatChannel.broadcast_to(message.recipient, payload)
  end

  # ---------- UPDATE ----------
  def broadcast_update(message)
    payload = {
      type: 'message_updated',
      message_id: message.id,
      content: message.content,
      edited_at: message.edited_at
    }

    ChatChannel.broadcast_to(message.sender, payload)
    ChatChannel.broadcast_to(message.recipient, payload)
  end

  # ---------- DELETE ----------
  def broadcast_delete(message)
    payload = {
      type: 'message_deleted',
      message_id: message.id
    }

    ChatChannel.broadcast_to(message.sender, payload)
    ChatChannel.broadcast_to(message.recipient, payload)
  end

  # ---------- MARK READ ----------
  def mark_conversation_as_read(target_id)
    messages = ChatMessage.where(
      sender_id: target_id,
      recipient_id: current_delegate.id,
      read_at: nil
    )

    messages.find_each do |msg|
      msg.update(read_at: Time.current)

      ChatChannel.broadcast_to(
        msg.sender,
        type: 'message_read',
        message_id: msg.id,
        read_at: msg.read_at
      )
    end


    Notification.where(
      delegate_id: current_delegate.id,
      notification_type: 'new_message',
      read_at: nil,
      notifiable_type: 'ChatMessage',
      notifiable_id: messages.pluck(:id)
    ).update_all(read_at: Time.current)

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
