# app/jobs/announcement_push_job.rb
class AnnouncementPushJob < ApplicationJob
  queue_as :default

  def perform(delegate_id, message, sent_at)
    delegate = Delegate.find_by(id: delegate_id)
    return unless delegate&.device_token.present?
    return if delegate.device_token.length < 20

    FcmService.send_push(
      token: delegate.device_token,
      title: "📢 WPA Announcement",
      body: message.truncate(100),
      data: {
        type: "admin_announce",
        sent_at: sent_at
      }
    )
  rescue => e
    Rails.logger.error "[AnnouncementPushJob] Failed for delegate #{delegate_id}: #{e.message}"
  end
end