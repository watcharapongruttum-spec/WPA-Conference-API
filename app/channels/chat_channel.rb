# app/channels/chat_channel.rb
require Rails.root.join('app/constants/chat_keys')

class ChatChannel < ApplicationCable::Channel

  def subscribed
    stream_for current_delegate

    REDIS.incr("chat:connections:#{current_delegate.id}")

    if params[:with_id].present?
      REDIS.setex(
        "chat:active_room:#{current_delegate.id}",
        3600,
        params[:with_id]
      )
    end

    # 🔴 FIX: ลบ REDIS.setex("chat:online:...") ออก
    # เดิมมี 2 บรรทัดที่ set online status คนละ key:
    #   REDIS.setex("chat:online:#{id}", ...)       ← key หนึ่ง
    #   Chat::PresenceService.online(id)             ← อีก key หนึ่ง ("online_user:#{id}")
    # ทำให้ PresenceService.online? คืน false เสมอ
    # แก้แล้วโดยให้ PresenceService เป็น single source of truth
    Chat::PresenceService.online(current_delegate.id)
  end

  def unsubscribed
    count = REDIS.decr("chat:connections:#{current_delegate.id}").to_i

    if count <= 0
      REDIS.del("chat:active_room:#{current_delegate.id}")
      REDIS.del("chat:connections:#{current_delegate.id}")
    end

    # 🔴 FIX: ลบ REDIS.del("chat:online:...") ออก
    # ให้ PresenceService จัดการ online key เพียงที่เดียว
    Chat::PresenceService.offline(current_delegate.id)
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
      recipient_id: payload['recipient_id'],
      content: payload['content']
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