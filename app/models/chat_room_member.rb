class ChatRoomMember < ApplicationRecord
  enum role: {
    member: 0,
    admin: 1
  }

  belongs_to :chat_room
  belongs_to :delegate

  validates :role, presence: true
end
