class NotificationDeliveryJob < ApplicationJob
  queue_as :default

  FCM_ALLOWED_TYPES = %w[new_message new_group_message admin_announce leave_reported].freeze

  BURST_WINDOW      = 60.seconds
  SUMMARY_THRESHOLD = 5

  def perform(notification_id)
    debug_id = SecureRandom.hex(4)
    Rails.logger.warn "🚀 [NDJ-#{debug_id}] START notification_id=#{notification_id}"

    notification = Notification.find_by(id: notification_id)
    unless notification
      Rails.logger.warn "❌ [NDJ-#{debug_id}] notification not found"
      return
    end

    Rails.logger.warn "📦 [NDJ-#{debug_id}] type=#{notification.notification_type} delegate_id=#{notification.delegate_id}"

    unless FCM_ALLOWED_TYPES.include?(notification.notification_type)
      Rails.logger.warn "⏭ [NDJ-#{debug_id}] skip type=#{notification.notification_type}"
      return
    end

    delegate = notification.delegate
    unless delegate&.device_token.present?
      Rails.logger.warn "⏭ [NDJ-#{debug_id}] no device token"
      return
    end

    Rails.logger.warn "📱 [NDJ-#{debug_id}] token=#{delegate.device_token.last(10)}"

    if Chat::PresenceService.online?(delegate.id)
      Rails.logger.warn "🟢 [NDJ-#{debug_id}] delegate online → skip FCM"
      return
    end

    recent = Notification.where(delegate: delegate)
                         .where(notification_type: notification.notification_type)
                         .where("created_at > ?", BURST_WINDOW.ago)
    count = recent.count

    Rails.logger.warn "📊 [NDJ-#{debug_id}] recent_count=#{count}"
    Rails.logger.warn "🧾 [NDJ-#{debug_id}] recent_ids=#{recent.pluck(:id)}"

    if count == 1
      Rails.logger.warn "📨 [NDJ-#{debug_id}] send_single"
      send_single(notification, debug_id)
    else
      Rails.logger.warn "📦 [NDJ-#{debug_id}] send_summary count=#{count}"
      send_summary(notification, count, debug_id)
    end
  rescue StandardError => e
    Rails.logger.error "💥 [NDJ-#{debug_id}] Failed: #{e.class} #{e.message}"
    Rails.logger.error e.backtrace.take(5).join("\n")
  end

  private

  def send_single(notification, debug_id)
    msg = notification.notifiable

    sender_name = if msg.respond_to?(:sender)
                    msg&.sender&.name
                  elsif msg.respond_to?(:reported_by)
                    msg&.reported_by&.name
                  end || "Someone"

    title, body = build_title_body(notification, msg, sender_name)

    Rails.logger.warn "🚀 [NDJ-#{debug_id}] CALL FCM single notifiable_id=#{notification.notifiable_id}"

    FcmService.send_push(
      token: notification.delegate.device_token,
      title: title,
      body:  body,
      data:  base_data(notification)
    )
  end

  def send_summary(notification, count, debug_id)
    Rails.logger.warn "🚀 [NDJ-#{debug_id}] CALL FCM summary count=#{count}"

    msg         = notification.notifiable
    delegate    = notification.delegate

    sender_name = if msg.respond_to?(:sender)
                    msg&.sender&.name
                  elsif msg.respond_to?(:reported_by)
                    msg&.reported_by&.name
                  end || "Someone"

    case notification.notification_type

    when "new_message"
      # ✅ เช็คว่ามีกี่คนส่งมาใน BURST_WINDOW
      recent_notif_ids = Notification
                           .where(delegate: delegate, notification_type: "new_message")
                           .where("created_at > ?", BURST_WINDOW.ago)
                           .pluck(:notifiable_id)

      unique_senders = ChatMessage
                         .where(id: recent_notif_ids)
                         .distinct
                         .pluck(:sender_id)

      if unique_senders.size > 1
        # ✅ หลายคนส่งมา — บอกจำนวนคน + จำนวนข้อความ
        title = "มีข้อความใหม่"
        body  = "#{unique_senders.size} คน ส่งข้อความมา #{count} ข้อความ"
      else
        # ✅ คนเดียวส่งมาหลายข้อความ — แสดง 4 ข้อความล่าสุด
        title = sender_name
        body  = recent_messages_body(msg.sender_id, msg.recipient_id, nil)
      end

    when "new_group_message"
      room_title = msg&.chat_room&.title || "Group Chat"

      recent_notif_ids = Notification
                           .where(delegate: delegate, notification_type: "new_group_message")
                           .where("created_at > ?", BURST_WINDOW.ago)
                           .pluck(:notifiable_id)

      unique_senders = ChatMessage
                         .where(id: recent_notif_ids)
                         .distinct
                         .pluck(:sender_id)

      if unique_senders.size > 1
        # ✅ หลายคนส่งใน group
        title = room_title
        body  = "#{unique_senders.size} คน ส่งข้อความมา #{count} ข้อความ"
      else
        # ✅ คนเดียวส่งหลายข้อความใน group
        title = room_title
        body  = recent_messages_body(msg.sender_id, nil, msg.chat_room_id, sender_name)
      end

    when "leave_reported"
      title = "แจ้งลาการนัดหมาย"
      body  = "มี #{count} รายการแจ้งลา"

    else
      title = "New Messages"
      body  = "มี #{count} ข้อความที่ยังไม่ได้อ่าน"
    end

    FcmService.send_push(
      token: delegate.device_token,
      title: title,
      body:  body,
      data:  base_data(notification)
    )
  end

  def build_title_body(notification, msg, sender_name)
    case notification.notification_type

    when "new_message"
      # ✅ ดึง 4 ข้อความล่าสุดจากคนส่งคนเดียวกัน (แบบ Messenger)
      body = recent_messages_body(msg.sender_id, msg.recipient_id, nil)
      [sender_name, body]

    when "new_group_message"
      room_title = msg&.chat_room&.title || "Group Chat"
      # ✅ ดึง 4 ข้อความล่าสุดใน group จากคนส่งคนเดียวกัน
      body = recent_messages_body(msg.sender_id, nil, msg.chat_room_id, sender_name)
      [room_title, body]

    when "leave_reported"
      ["แจ้งลาการนัดหมาย", "#{sender_name} ขอยกเลิกการนัดหมาย"]

    else
      ["Notification", msg&.content&.truncate(80).to_s]
    end
  end

  # ✅ helper — ดึง 4 ข้อความล่าสุด แล้ว join ด้วย \n
  def recent_messages_body(sender_id, recipient_id, chat_room_id, prefix = nil)
    scope = ChatMessage
              .where(sender_id: sender_id, deleted_at: nil, message_type: "text")
              .where.not(content: [nil, ""])

    scope = chat_room_id.present? \
              ? scope.where(chat_room_id: chat_room_id) \
              : scope.where(recipient_id: recipient_id, chat_room_id: nil)

    messages = scope.order(created_at: :desc).limit(4).pluck(:content).reverse

    if prefix.present?
      messages.map { |c| "#{prefix}: #{c.truncate(80)}" }.join("\n")
    else
      messages.map { |c| c.truncate(80) }.join("\n")
    end
  end

  def base_data(notification)
    msg = notification.notifiable

    sender_id    = msg&.sender_id    if msg.respond_to?(:sender_id)
    chat_room_id = msg&.chat_room_id if msg.respond_to?(:chat_room_id)

    {
      type:            notification.notification_type,
      message_id:      notification.notifiable_id.to_s,
      notification_id: notification.id.to_s,
      screen:          "chat",
      sender_id:       sender_id.to_s,
      chat_room_id:    chat_room_id.to_s
    }
  end
end