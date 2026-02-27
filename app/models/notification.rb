class Notification < ApplicationRecord
  belongs_to :delegate
  belongs_to :notifiable, polymorphic: true, optional: true

  self.inheritance_column = :_type_disabled

  scope :unread, -> { where(read_at: nil) }
  scope :read,   -> { where.not(read_at: nil) }

  def mark_as_read!
    update(read_at: Time.current) if read_at.nil?
  end

  def unread?
    read_at.nil?
  end

  # ✅ ใช้สำหรับ badge count (เหมือน Facebook)
  def self.unread_count_for(delegate)
    unread.where(delegate: delegate).count
  end
end
