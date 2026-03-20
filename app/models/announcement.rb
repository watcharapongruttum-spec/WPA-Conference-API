# app/models/announcement.rb
class Announcement < ApplicationRecord
  has_many :notifications, as: :notifiable
  validates :message, presence: true

  # ✅ stub associations ที่ Rails จะ preload
  belongs_to :sender,    optional: true, class_name: "Delegate"
  belongs_to :requester, optional: true, class_name: "Delegate"
  belongs_to :target,    optional: true, class_name: "Delegate"
end

