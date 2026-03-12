# app/services/fcm_notifier.rb
#
# High-level FCM notification sender
# รู้จัก business logic — ว่าจะส่ง title/body อะไรสำหรับแต่ละ type
#
# FcmService  = low-level HTTP wrapper (ไม่ต้องแตะ)
# FcmNotifier = high-level — ใช้ที่นี่ที่เดียว
#
class FcmNotifier

  # ─── Direct Message ───────────────────────────────────
  def self.new_message(delegate:, message:)
    return unless pushable?(delegate)

    sender_name = message.sender&.name || "Someone"
    body        = message.image? ? "📷 รูปภาพ" : message.content.to_s.truncate(80)

    push(
      delegate: delegate,
      title:    "New Message",
      body:     "#{sender_name}: #{body}",
      data:     { type: "new_message", message_id: message.id.to_s, screen: "chat" }
    )
  end

  # ─── Group Message ────────────────────────────────────
  def self.new_group_message(delegate:, message:)
    return unless pushable?(delegate)

    room_title  = message.chat_room&.title || "Group Chat"
    sender_name = message.sender&.name || "Someone"
    body        = message.image? ? "📷 รูปภาพ" : message.content.to_s.truncate(80)

    push(
      delegate: delegate,
      title:    room_title,
      body:     "#{sender_name}: #{body}",
      data:     { type: "new_group_message", room_id: message.chat_room_id.to_s, screen: "chat" }
    )
  end

  # ─── Leave Reported ───────────────────────────────────
  def self.leave_reported(delegate:, leave_form:)
    return unless pushable?(delegate)

    reporter_name = leave_form.reported_by&.name || "Someone"

    push(
      delegate: delegate,
      title:    "แจ้งลาการนัดหมาย",
      body:     "#{reporter_name} ขอยกเลิกการนัดหมาย",
      data:     { type: "leave_reported", leave_form_id: leave_form.id.to_s, screen: "schedule" }
    )
  end

  # ─── Admin Announce ───────────────────────────────────
  def self.announce(delegate:, message:, sent_at:)
    return unless pushable?(delegate)

    push(
      delegate: delegate,
      title:    "📢 WPA Announcement",
      body:     message.to_s.truncate(100),
      data:     { type: "admin_announce", sent_at: sent_at.to_s, screen: "home" }
    )
  end

  # ─── Summary (burst) ──────────────────────────────────
  # ใช้เมื่อมี notification หลายอันในช่วงเวลาสั้น
  def self.summary(delegate:, notification_type:, count:, context: {})
    return unless pushable?(delegate)

    title = case notification_type
            when "new_group_message" then context[:room_title] || "Group Chat"
            when "leave_reported"    then "แจ้งลาการนัดหมาย"
            else "New Messages"
            end

    push(
      delegate: delegate,
      title:    title,
      body:     "You have #{count} unread notifications",
      data:     { type: notification_type, screen: "chat" }
    )
  end

  # ─── Private ──────────────────────────────────────────
  private

  def self.pushable?(delegate)
    delegate&.device_token.present? && delegate.device_token.length >= 20
  end

  def self.push(delegate:, title:, body:, data: {})
    FcmService.send_push(
      token: delegate.device_token,
      title: title,
      body:  body,
      data:  data
    )
  end

  private_class_method :pushable?, :push
end