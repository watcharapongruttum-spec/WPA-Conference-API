# app/controllers/api/v1/admin/announcements_controller.rb
class Api::V1::Admin::AnnouncementsController < Api::V1::BaseController

  # POST /api/v1/admin/announcements
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

      # ✅ 2. FCM Push (ตอนแอปปิดอยู่)
      if delegate.device_token.present? && delegate.device_token.length >= 20
        FcmService.send_push(
          token: delegate.device_token,
          title: "📢 WPA Announcement",
          body: message.truncate(100),
          data: {
            type: "admin_announce",
            sent_at: sent_at
          }
        )
        push_count += 1
      end
    end

    Rails.logger.info "📢 Announcement sent — FCM pushed to #{push_count} devices"

    render json: {
      status: "ok",
      message: message,
      push_sent: push_count
    }, status: :ok
  end

end