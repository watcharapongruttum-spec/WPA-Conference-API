# app/jobs/group_message_push_job.rb
class GroupMessagePushJob < ApplicationJob
  queue_as :default

  def perform(delegate_id:, room_id:, room_title:, sender_name:, content:)
    delegate = Delegate.find_by(id: delegate_id)
    return unless delegate&.device_token.present?
    return if delegate.device_token.length < 20

    FcmService.send_push(
      token: delegate.device_token,
      title: room_title.to_s,
      body: "#{sender_name}: #{content.truncate(100)}",
      data: {
        type: "group_message",
        room_id: room_id.to_s
      }
    )
  rescue StandardError => e
    Rails.logger.error "[GroupMessagePushJob] Failed: #{e.message}"
  end
end
