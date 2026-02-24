class Api::V1::Admin::AnnouncementsController < Api::V1::BaseController

  # POST /api/v1/admin/announcements
  def create
    # รองรับทั้ง {"message": "..."} และ {"notification": {"message": "..."}}
    message = params[:message] || params.dig(:notification, :message)

    if message.blank?
      render json: { error: "message is required" }, status: :unprocessable_entity
      return
    end

    Delegate.find_each do |delegate|
      NotificationChannel.broadcast_to(delegate, {
        type: "admin_announce",
        message: message,
        sent_at: Time.current.iso8601
      })
    end

    render json: { status: "ok", message: message }, status: :ok
  end

end