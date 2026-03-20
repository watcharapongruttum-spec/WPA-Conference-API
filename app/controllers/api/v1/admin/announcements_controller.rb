class Api::V1::Admin::AnnouncementsController < ApplicationController
  def create
    message = params[:message] || params.dig(:notification, :message)

    if message.blank?
      render json: { error: "message is required" }, status: :unprocessable_entity
      return
    end

    announcement = Announcement.create!(
      message: message,
      sent_at: Time.current
    )

    # ✅ Real-time ครั้งเดียว — ทุกคนรับพร้อมกันเลย
    ActionCable.server.broadcast("notifications:year:2025", {
      type:    "admin_announce",
      message: message,
      sent_at: announcement.sent_at.iso8601
    })

    # ✅ สร้าง Notification record + FCM ใน background
    AnnouncementBroadcastJob.perform_later(announcement.id)

    render json: {
      status:          "ok",
      message:         message,
      announcement_id: announcement.id
    }, status: :ok
  end
end