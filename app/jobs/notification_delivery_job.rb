class NotificationDeliveryJob < ApplicationJob
  queue_as :default

  # ✅ FIX #3: เพิ่ม new_group_message ให้ตรงกับ BroadcastService
  # เดิมขาด new_group_message ทำให้ group chat push ถูก skip ทุกครั้ง
  FCM_ALLOWED_TYPES = %w[new_message new_group_message admin_announce].freeze

  BURST_WINDOW = 60.seconds
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

    elsif count <= SUMMARY_THRESHOLD
      Rails.logger.warn "🤐 [NDJ-#{debug_id}] burst suppressed"
      nil

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
    sender_name = msg&.sender&.name || "Someone"

    Rails.logger.warn "🚀 [NDJ-#{debug_id}] CALL FCM single message_id=#{notification.notifiable_id}"

    FcmService.send_push(
      token: notification.delegate.device_token,
      title: "New Message",
      body: "#{sender_name}: #{msg&.content&.truncate(80)}",
      data: base_data(notification)
    )
  end

  def send_summary(notification, count, debug_id)
    Rails.logger.warn "🚀 [NDJ-#{debug_id}] CALL FCM summary count=#{count}"

    FcmService.send_push(
      token: notification.delegate.device_token,
      title: "You have #{count} new messages",
      body: "+#{count} new messages",
      data: base_data(notification)
    )
  end

  def base_data(notification)
    {
      type: notification.notification_type,
      message_id: notification.notifiable_id.to_s,
      notification_id: notification.id.to_s,
      screen: "chat"
    }
  end
end
