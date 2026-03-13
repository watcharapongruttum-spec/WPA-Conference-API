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
    # target_id = payload["user_id"]
    target_id = payload["recipient_id"] || payload["user_id"]

    # ✅ ใช้ key เดียวกับ SendMessageService — ไม่ hardcode key ซ้ำซ้อน
    REDIS.setex("chat:active_room:#{current_delegate.id}", 3600, target_id.to_s)

    Chat::ReadService.mark_room(current_delegate.id, target_id)
  end

  def leave_room(data)
    # ✅ ลบแค่ key เดียว ไม่มี "chat:room:..." อีกต่อไป
    REDIS.del("chat:active_room:#{current_delegate.id}")
  end

  def send_message(data)
    payload = safe_json(data)
    message = Chat::SendMessageService.call(
      sender:       current_delegate,
      recipient_id: payload["recipient_id"],
      content:      payload["content"]
    )

    broadcast_message(message)

    # ✅ ตรวจหลัง SendMessageService — ถ้า recipient เปิดห้องอยู่
    # SendMessageService จะ mark read ไปแล้ว (read_at จะมีค่า)
    # → ไม่ต้องสร้าง notification / ส่ง push
    Notifications::Pipeline.call(message) unless message.read_at.present?
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

    broadcast_message(message)

    # ✅ เหมือน send_message — skip notification ถ้าอ่านแล้ว
    Notifications::Pipeline.call(message) unless message.read_at.present?
  rescue ArgumentError => e
    handle_error(e)
  rescue StandardError => e
    handle_error(e)
  end

  private

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