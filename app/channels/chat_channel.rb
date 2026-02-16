require Rails.root.join('app/constants/chat_keys')

class ChatChannel < ApplicationCable::Channel

  # ================= SUBSCRIBE =================
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
    payload = safe_json(data)
    target_delegate_id = payload["target_id"]

    ChatChannel.broadcast_to(
      Delegate.find(target_delegate_id),
      {
        type: "typing",
        from: current_delegate.id
      }
    )
  end

  # ================= ENTER ROOM =================
  def enter_room(data)
    payload = safe_json(data)

    target_delegate_id  = payload["user_id"]
    current_delegate_id = current_delegate.id

    Chat::RoomStateService.open_room(current_delegate_id, target_delegate_id)
    Chat::RoomStateService.read_if_unlocked(current_delegate_id, target_delegate_id)
  end

  # ================= LEAVE ROOM =================
  def leave_room(data)
    payload = safe_json(data)
    target_delegate_id = payload["user_id"]

    Chat::RoomStateService.close_room(current_delegate.id, target_delegate_id)
  end

  # ================= SEND MESSAGE (WS) =================
  def send_message(data)
    payload = safe_json(data)

    message = Chat::SendMessageService.call(
      sender: current_delegate,
      recipient_id: payload['recipient_id'],
      content: payload['content']
    )

    Notification::CreateService.call(message)

  rescue => e
    handle_error(e)
  end

  # ================= READ MESSAGE =================
  def read_message(data)
    payload = safe_json(data)
    message = ChatMessage.find_by(id: payload['message_id'])
    return unless message && message.recipient == current_delegate

    Chat::ReadService.mark_one(message)
  end

  # =========================================================
  # PRIVATE
  # =========================================================
  private

  # ---------- JSON ----------
  def safe_json(data)
    data.is_a?(String) ? JSON.parse(data) : data
  end

  # ---------- SERIALIZER ----------
  def serializer(message)
    Api::V1::ChatMessageSerializer
      .new(message)
      .serializable_hash[:data]
  end

  # ---------- ROOM STATE ----------
  def recipient_open_room?(message)
    Chat::RoomStateService.recipient_open?(
      message.recipient_id,
      message.sender_id
    )
  end

  # ---------- ERROR ----------
  def handle_error(error)
    Rails.logger.error "❌ ChatChannel error: #{error.class} - #{error.message}"
    transmit(type: 'error', message: error.message)
  end
end
