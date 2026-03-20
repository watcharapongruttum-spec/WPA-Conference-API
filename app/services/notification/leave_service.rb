# app/services/notification/leave_service.rb
# แจ้งเตือน booker ของ schedule เมื่อมีการยื่นใบลา
class Notification::LeaveService
  def self.call(leave_form)
    return unless leave_form&.schedule

    reporter = leave_form.reported_by
    # FIX: ใช้ booker_delegate แทน booker เพราะ booker_id คือ team_id ไม่ใช่ delegate_id
    booker   = leave_form.schedule.booker_delegate

    # ไม่แจ้งถ้าไม่มี booker หรือ booker เป็นคนเดียวกับผู้ยื่น
    return if booker.nil? || booker.id == reporter.id

    notification = ::Notification.create!(
      delegate:          booker,
      notification_type: "leave_reported",
      notifiable:        leave_form
    )

    Rails.cache.delete("dashboard:#{booker.id}:v1")
    Notification::BroadcastService.call(notification)

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[LeaveService] Failed to create notification: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "[LeaveService] Unexpected error: #{e.message}"
  end
end