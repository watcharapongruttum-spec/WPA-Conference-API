class RoomMember < ApplicationRecord
  belongs_to :chat_room
  belongs_to :delegate
end
