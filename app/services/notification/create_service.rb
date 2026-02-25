# app/services/notification/create_service.rb
class Notification::CreateService
  def self.call(message)
    lock_key = "notif_lock:#{message.id}"

    # 🔴 FIX 5: เปลี่ยนจาก GET+SET แยกกัน → SET NX (atomic)
    # เดิม: GET → return ถ้ามี → SET (2 operations → race condition)
    # ถ้า REST + WebSocket ยิงพร้อมกัน ทั้งคู่ GET ก่อน SET → ได้ notification ซ้ำ
    acquired = REDIS.set(lock_key, 1, nx: true, ex: 5)
    return unless acquired

    recipient = message.recipient
    return unless recipient

    notification = ::Notification.create!(
      delegate:          recipient,
      notification_type: 'new_message',
      notifiable:        message
    )

    # 🔴 FIX 2: clear dashboard cache ของ recipient
    # เดิมไม่ได้ delete → new_messages_count ค้าง (stale) นาน 30 วินาที
    Rails.cache.delete("dashboard:#{recipient.id}:v1")

    Notification::BroadcastService.call(notification)
  end
end