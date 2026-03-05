# app/controllers/api/v1/admin/announcements_controller.rb
class Api::V1::Admin::AnnouncementsController < ApplicationController
  def create
    message = params[:message] || params.dig(:notification, :message)

    if message.blank?
      render json: { error: "message is required" }, status: :unprocessable_entity
      return
    end

    sent_at = Time.current.iso8601
    push_count = 0

    Delegate.find_each do |delegate|
      # ✅ 1. Real-time ผ่าน ActionCable (ตอนแอปเปิดอยู่)
      NotificationChannel.broadcast_to(delegate, {
                                         type: "admin_announce",
                                         message: message,
                                         sent_at: sent_at
                                       })

      # ✅ 2. FCM Push ผ่าน Background Job (ไม่ block request แล้ว)
      if delegate.device_token.present? && delegate.device_token.length >= 20
        AnnouncementPushJob.perform_later(delegate.id, message, sent_at)
        push_count += 1
      end
    end

    Rails.logger.info "📢 Announcement queued — FCM jobs enqueued for #{push_count} devices"

    render json: {
      status: "ok",
      message: message,
      push_queued: push_count # เปลี่ยนชื่อ key ให้ตรงความจริง
    }, status: :ok
  end
end
