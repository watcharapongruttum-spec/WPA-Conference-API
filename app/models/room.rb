# app/models/chat_room.rb
class ChatRoom < ApplicationRecord
  has_many :room_members, dependent: :destroy
  has_many :delegates, through: :room_members
  has_many :chat_messages, dependent: :destroy
  
  # กำหนด enum ให้ถูกต้อง
  enum room_kind: { direct: 0, group: 1, event: 2 }
  
  validates :title, presence: true
end