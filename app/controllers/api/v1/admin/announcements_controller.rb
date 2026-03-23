# app/controllers/api/v1/admin/announcements_controller.rb
class Api::V1::Admin::AnnouncementsController < Api::V1::Admin::BaseController
  def index
    page     = (params[:page] || 1).to_i
    per_page = [(params[:per_page] || 20).to_i, 100].min

    announcements = Announcement
                      .order(sent_at: :desc)
                      .offset((page - 1) * per_page)
                      .limit(per_page)

    total = Announcement.count

    render json: {
      total:         total,
      page:          page,
      per_page:      per_page,
      total_pages:   (total.to_f / per_page).ceil,
      announcements: announcements.map { |a|
        {
          id:      a.id,
          message: a.message,
          sent_at: a.sent_at&.iso8601
        }
      }
    }
  end

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

    ActionCable.server.broadcast("notifications:year:2025", {
      type:    "admin_announce",
      message: message,
      sent_at: announcement.sent_at.iso8601
    })

    AnnouncementBroadcastJob.perform_later(announcement.id)

    render json: {
      status:          "ok",
      message:         message,
      announcement_id: announcement.id
    }, status: :ok
  end
end