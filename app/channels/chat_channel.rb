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

  # ✅ เพิ่ม: typing indicator
  def typing_start(data)
    payload = safe_json(data)
    recipient = Delegate.find_by(id: payload["recipient_id"])
    return unless recipient

    ChatChannel.broadcast_to(recipient, {
                               type: "typing_start",
                               sender_id: current_delegate.id
                             })
  end

  def typing_stop(data)
    payload = safe_json(data)
    recipient = Delegate.find_by(id: payload["recipient_id"])
    return unless recipient

    ChatChannel.broadcast_to(recipient, {
                               type: "typing_stop",
                               sender_id: current_delegate.id
                             })
  end

  def enter_room(data)
    payload = safe_json(data)
    target_id = payload["user_id"]
    REDIS.set("chat:room:#{current_delegate.id}:#{target_id}", "open")
    REDIS.set("chat:active_room:#{current_delegate.id}", target_id.to_s)
    Chat::ReadService.mark_room(current_delegate.id, target_id)
  end

  def leave_room(data)
    payload = safe_json(data)
    target_id = payload["user_id"]
    REDIS.del("chat:room:#{current_delegate.id}:#{target_id}")
    REDIS.del("chat:active_room:#{current_delegate.id}")
  end

  def send_message(data)
    payload = safe_json(data)
    message = Chat::SendMessageService.call(
      sender: current_delegate,
      recipient_id: payload["recipient_id"],
      content: payload["content"]
    )
    Notification::CreateService.call(message)
  rescue StandardError => e
    handle_error(e)
  end

  private

  def safe_json(data)
    data.is_a?(String) ? JSON.parse(data) : data
  end

  def handle_error(error)
    Rails.logger.error "❌ ChatChannel error: #{error.class} - #{error.message}"
    transmit(type: "error", message: error.message)
  end
end
