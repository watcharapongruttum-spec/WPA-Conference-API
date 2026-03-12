# app/channels/chat_channel.rb
require Rails.root.join("app/constants/chat_keys")

class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_delegate
    Chat::PresenceService.online(current_delegate.id)
    return unless params[:with_id].present?
    REDIS.setex(
      "chat:active_room:#{current_delegate.id}",
      3600,
      params[:with_id]
    )
  end

  def unsubscribed
    remaining = Chat::PresenceService.offline(current_delegate.id)
    return unless remaining <= 0
    REDIS.del("chat:active_room:#{current_delegate.id}")
  end

  def ping(_data)
    Chat::PresenceService.refresh(current_delegate.id)
  end

  def typing_start(data)
    payload   = safe_json(data)
    recipient = Delegate.find_by(id: payload["recipient_id"])
    return unless recipient
    ChatChannel.broadcast_to(recipient, {
      type:      "typing_start",
      sender_id: current_delegate.id
    })
  end

  def typing_stop(data)
    payload   = safe_json(data)
    recipient = Delegate.find_by(id: payload["recipient_id"])
    return unless recipient
    ChatChannel.broadcast_to(recipient, {
      type:      "typing_stop",
      sender_id: current_delegate.id
    })
  end

  def enter_room(data)
    payload   = safe_json(data)
    target_id = payload["user_id"]
    REDIS.set("chat:room:#{current_delegate.id}:#{target_id}", "open")
    REDIS.set("chat:active_room:#{current_delegate.id}", target_id.to_s)
    Chat::ReadService.mark_room(current_delegate.id, target_id)
  end

  def leave_room(data)
    payload   = safe_json(data)
    target_id = payload["user_id"]
    REDIS.del("chat:room:#{current_delegate.id}:#{target_id}")
    REDIS.del("chat:active_room:#{current_delegate.id}")
  end

  def send_message(data)
    payload = safe_json(data)
    message = Chat::SendMessageService.call(
      sender:       current_delegate,
      recipient_id: payload["recipient_id"],
      content:      payload["content"]
    )
    Notifications::Pipeline.call(message)  # ✅ แก้จาก Notification::CreateService
    broadcast_message(message)
    auto_read_if_open(message)             # ✅ อ่านอัตโนมัติถ้า recipient เปิดห้องอยู่
  rescue StandardError => e
    handle_error(e)
  end

  def send_image(data)
    payload  = safe_json(data)
    data_uri = payload["image"]
    return transmit(type: "error", message: "No image provided") if data_uri.blank?
    message = Chat::SendImageService.call(
      sender:       current_delegate,
      recipient_id: payload["recipient_id"],
      data_uri:     data_uri
    )
    Notifications::Pipeline.call(message)  # ✅ แก้จาก Notification::CreateService
    broadcast_message(message)
    auto_read_if_open(message)             # ✅ อ่านอัตโนมัติถ้า recipient เปิดห้องอยู่
  rescue ArgumentError => e
    handle_error(e)
  rescue StandardError => e
    handle_error(e)
  end

  private

  # ✅ ถ้า recipient เปิดห้องนี้อยู่ → mark_one ทันที
  def auto_read_if_open(message)
    recipient_id  = message.recipient_id
    sender_id     = message.sender_id
    room_open_key = "chat:room:#{recipient_id}:#{sender_id}"

    return unless REDIS.get(room_open_key) == "open"

    Chat::ReadService.mark_one(message)
  rescue StandardError => e
    Rails.logger.warn "[ChatChannel] auto_read failed: #{e.message}"
  end

  def broadcast_message(message)
    message = ChatMessage
                .includes(sender: :company, recipient: :company)
                .find(message.id)
    payload = {
      type:    "new_message",
      message: Api::V1::ChatMessageSerializer.new(message).serializable_hash
    }
    ChatChannel.broadcast_to(message.recipient, payload)
    ChatChannel.broadcast_to(message.sender,    payload)
  end

  def safe_json(data)
    data.is_a?(String) ? JSON.parse(data) : data
  end

  def handle_error(error)
    Rails.logger.error "❌ ChatChannel error: #{error.class} - #{error.message}"
    transmit({ type: "error", message: error.message })
  end
end