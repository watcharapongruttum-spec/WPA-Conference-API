# app/channels/chat_channel.rb
require Rails.root.join('app/constants/chat_keys')

class ChatChannel < ApplicationCable::Channel

  def subscribed
    stream_for current_delegate

    # ✅ PresenceService จัดการ connection count + online key รวมกัน
    Chat::PresenceService.online(current_delegate.id)

    if params[:with_id].present?
      REDIS.setex(
        "chat:active_room:#{current_delegate.id}",
        3600,
        params[:with_id]
      )
    end
  end

  def unsubscribed
    # ✅ offline() จะเช็ค count เอง — ถ้า multi-device ยังไม่ del online key
    remaining = Chat::PresenceService.offline(current_delegate.id)

    if remaining <= 0
      REDIS.del("chat:active_room:#{current_delegate.id}")
    end
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
      sender:       current_delegate,
      recipient_id: payload['recipient_id'],
      content:      payload['content']
    )

    Notification::CreateService.call(message)

  rescue => e
    handle_error(e)
  end

  private

  def safe_json(data)
    data.is_a?(String) ? JSON.parse(data) : data
  end

  def handle_error(error)
    Rails.logger.error "❌ ChatChannel error: #{error.class} - #{error.message}"
    transmit(type: 'error', message: error.message)
  end
end