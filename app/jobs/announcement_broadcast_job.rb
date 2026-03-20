class AnnouncementBroadcastJob < ApplicationJob
  queue_as :default

  YEAR = "2025"

  def perform(announcement_id)
    announcement = Announcement.find_by(id: announcement_id)
    return unless announcement

    delegate_ids = delegates_2025_ids
    return if delegate_ids.empty?

    now = Time.current

    # ✅ INSERT ครั้งเดียว แทน 145 ครั้ง
    rows = delegate_ids.map do |id|
      {
        delegate_id:       id,
        notification_type: "admin_announce",
        notifiable_type:   "Announcement",
        notifiable_id:     announcement.id,
        read_at:           nil,
        created_at:        now,
        updated_at:        now
      }
    end

    Notification.insert_all(rows)

    # ✅ FCM — เฉพาะคนที่มี device_token
    Delegate.where(id: delegate_ids)
            .where.not(device_token: nil)
            .where("LENGTH(device_token) >= 20")
            .pluck(:id)
            .each do |id|
              AnnouncementPushJob.perform_later(
                id,
                announcement.message,
                announcement.sent_at.iso8601
              )
            end

    # ✅ bulk delete cache ครั้งเดียว
    keys = delegate_ids.map { |id| "dashboard:#{id}:v1" }
    Rails.cache.delete_multi(keys)
  end

  private

  def delegates_2025_ids
    Delegate.where(<<~SQL, YEAR).pluck(:id)
      EXISTS (
        SELECT 1
        FROM schedules s
        JOIN conference_dates cd ON cd.id = s.conference_date_id
        JOIN conferences co      ON co.id = cd.conference_id
        WHERE co.conference_year = ?
          AND (
            s.booker_id  = delegates.id
            OR s.delegate_id = delegates.id
            OR s.target_id   = delegates.team_id
          )
      )
    SQL
  end
end