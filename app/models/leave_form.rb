class LeaveForm < ApplicationRecord
  belongs_to :schedule
  belongs_to :leave_type
  belongs_to :reported_by, class_name: "Delegate"

  enum status: {
    reported: "reported",
    approved: "approved",
    rejected: "rejected"
  }

  # =========================
  # BULK LEAVE — Partial success (ไม่ใช้ transaction เพื่อให้บางตัว save ได้)
  # =========================
  def self.bulk_report!(leaves:, reporter:)
    raise "leaves is required" if leaves.blank?

    created_ids = []
    errors      = []

    leaves.each do |leave|
      lf = create!(
        schedule_id: leave[:schedule_id],
        leave_type_id: leave[:leave_type_id],
        explanation: leave[:explanation],
        reported_by_id: reporter.id,
        status: "reported",
        reported_at: Time.current
      )
      created_ids << lf.id




      Notification::LeaveService.call(lf)

    rescue StandardError => e
      errors << {
        schedule_id: leave[:schedule_id],
        message: e.message
      }
    end

    
    {
      success: errors.empty?,
      created_count: created_ids.size,
      created_ids: created_ids,
      errors: errors
    }
  end
end
