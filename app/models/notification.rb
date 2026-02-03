class Notification < ApplicationRecord
  belongs_to :delegate
  belongs_to :notifiable, polymorphic: true, optional: true
  
  # ปิดการใช้งาน STI บนคอลัมน์ type
  self.inheritance_column = :_type_disabled
  
  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  
  def mark_as_read!
    update(read_at: Time.current) if read_at.nil?
  end
  
  def unread?
    read_at.nil?
  end
end
