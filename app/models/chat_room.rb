class ChatRoom < ApplicationRecord
  # enum room_kind: {
  #   direct: 0,
  #   group_chat: 1,
  #   broadcast: 2
  # }
  enum room_kind: { direct: 0, group: 1, event: 2 }, _prefix: true

  has_many :chat_room_members, dependent: :destroy
  has_many :delegates, through: :chat_room_members
  has_many :chat_messages, dependent: :destroy

  validates :room_kind, presence: true
  validates :title, presence: true

  # ใช้เช็คสิทธิ์การส่งข้อความ
  # def can_send_message?(delegate)
  #   return true unless broadcast?
  #   chat_room_members.exists?(delegate: delegate, role: :admin)
  # end

  def can_send_message?(delegate)
    return true unless room_kind_event?
    chat_room_members.exists?(delegate: delegate, role: :admin)
  end


end
