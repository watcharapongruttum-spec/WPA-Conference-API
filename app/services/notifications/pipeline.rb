# app/services/notification/pipeline.rb
#
# Single entry point สำหรับ notification flow ทุก type
#
# ทำ 2 อย่างเสมอ:
#   1. ActionCable → in-app real-time (ทุก type)
#   2. FCM via Job → push notification (เฉพาะ type ที่อนุญาต + delegate offline)
#
module Notifications
  class Pipeline

    FCM_TYPES = %w[new_message new_group_message leave_reported].freeze

    # ─── Direct Chat ──────────────────────────────────────
    def self.call(message)
      recipient = message.recipient
      return unless recipient
      return unless acquire_lock("notif_lock:#{message.id}")

      notification = create!(
        delegate:          recipient,
        notification_type: "new_message",
        notifiable:        message
      )
      deliver(notification)
    end

    # ─── Group Chat ───────────────────────────────────────
    def self.call_group(message, room:, sender:)
      recipient_ids = room.chat_room_members
                          .where.not(delegate_id: sender.id)
                          .pluck(:delegate_id)

      delegates = Delegate.where(id: recipient_ids).index_by(&:id)

      recipient_ids.each do |delegate_id|
        next if room_open?(room.id, delegate_id)

        delegate = delegates[delegate_id]
        next unless delegate

        notification = create!(
          delegate:          delegate,
          notification_type: "new_group_message",
          notifiable:        message
        )
        Rails.cache.delete("dashboard:#{delegate_id}:v1")
        deliver(notification)
      rescue StandardError => e
        Rails.logger.error "[Notification::Pipeline] group delegate=#{delegate_id}: #{e.message}"
      end
    end

    # ─── Leave Form ───────────────────────────────────────
    def self.call_leave(leave_form)
      return unless leave_form&.schedule

      booker   = leave_form.schedule.booker
      reporter = leave_form.reported_by
      return if booker.nil? || booker.id == reporter.id

      notification = create!(
        delegate:          booker,
        notification_type: "leave_reported",
        notifiable:        leave_form
      )
      Rails.cache.delete("dashboard:#{booker.id}:v1")
      deliver(notification)
    end

    # ─── Connection Events ────────────────────────────────
    def self.call_connection(delegate:, type:, notifiable:)
      notification = create!(
        delegate:          delegate,
        notification_type: type,
        notifiable:        notifiable
      )
      Rails.cache.delete("dashboard:#{delegate.id}:v1")
      # connection events → ActionCable only (ไม่มี FCM)
      broadcast_ws(notification)
    end

    # ─── Admin Announce ───────────────────────────────────
    def self.call_announce(delegate:, message:, sent_at:)
      # ActionCable
      NotificationChannel.broadcast_to(delegate, {
        type:    "new_notification",
        payload: { type: "admin_announce", message: message, sent_at: sent_at }
      })

      # FCM via Job (ไม่ผ่าน Pipeline เพราะไม่มี Notification record)
      AnnouncementPushJob.perform_later(delegate.id, message, sent_at)
    end

    # ─── Private ──────────────────────────────────────────
    private

    def self.create!(attrs)
      ::Notification.create!(attrs)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[Notification::Pipeline] create! failed: #{e.message}"
      raise
    end

    # 1. ActionCable (ทุก type)
    # 2. FCM Job (เฉพาะ FCM_TYPES + offline)
    def self.deliver(notification)
      broadcast_ws(notification)
      enqueue_fcm(notification) if FCM_TYPES.include?(notification.notification_type)
    end

    def self.broadcast_ws(notification)
      NotificationChannel.broadcast_to(
        notification.delegate,
        {
          type:         "new_notification",
          notification: Api::V1::NotificationSerializer.new(notification).serializable_hash
        }
      )
    end

    def self.enqueue_fcm(notification)
      return if Chat::PresenceService.online?(notification.delegate_id)

      NotificationDeliveryJob.set(wait: 3.seconds).perform_later(notification.id)
    end

    def self.room_open?(room_id, delegate_id)
      REDIS.get("group_chat_open:#{room_id}:#{delegate_id}") == "1"
    rescue Redis::BaseError
      false
    end

    def self.acquire_lock(key)
      REDIS.set(key, 1, nx: true, ex: 5)
    rescue Redis::BaseError => e
      Rails.logger.warn "[Notification::Pipeline] Redis lock failed: #{e.message}"
      true # fallback: ส่งต่อได้ (อาจซ้ำในกรณีหายาก)
    end

    private_class_method :create!, :deliver, :broadcast_ws, :enqueue_fcm, :room_open?, :acquire_lock
  end
end