require Rails.root.join('app/constants/chat_keys')

class ChatChannel < ApplicationCable::Channel

  def subscribed
    stream_for current_delegate

    # ใช้ counter แทน simple flag — รองรับหลาย connection พร้อมกัน
    REDIS.incr("chat:connections:#{current_delegate.id}")
    REDIS.setex("chat:online:#{current_delegate.id}", 3600, "1")

    if params[:with_id].present?
      REDIS.setex(
        "chat:active_room:#{current_delegate.id}",
        3600,
        params[:with_id]
      )
    end

    Chat::PresenceService.online(current_delegate.id)
    # ❌ ไม่ mark_all_for_user ตอน connect — ต้อง enter_room ก่อน
  end

  def unsubscribed
    # ลด counter — ลบ key เฉพาะเมื่อไม่มี connection เหลือแล้วเท่านั้น
    count = REDIS.decr("chat:connections:#{current_delegate.id}").to_i

    if count <= 0
      REDIS.del("chat:online:#{current_delegate.id}")
      REDIS.del("chat:active_room:#{current_delegate.id}")
      REDIS.del("chat:connections:#{current_delegate.id}")
    end

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
    # ✅ ล้าง active_room เมื่อ user ออกจากหน้า chat จริงๆ
    # ป้องกัน auto-mark ข้อความที่ user ไม่ได้เห็น
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