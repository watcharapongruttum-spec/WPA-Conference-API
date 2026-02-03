class ChatMessage < ApplicationRecord
  belongs_to :chat_room, optional: true
  belongs_to :sender, class_name: "Delegate"
  belongs_to :recipient,
             class_name: "Delegate",
             foreign_key: "recipient_id",
             optional: true

  validates :content, presence: true
  validate :can_send_message

  after_create_commit :broadcast_message

  private

  def can_send_message
    return if chat_room.nil?

    unless chat_room.can_send_message?(sender)
      errors.add(:base, "Cannot send message")
    end
  end

  def broadcast_message
    return unless chat_room

    ChatRoomChannel.broadcast_to(
      chat_room,
      {
        id: id,
        room_id: chat_room_id,
        sender_id: sender_id,
        content: content,
        created_at: created_at.strftime("%H:%M")
      }
    )
  end
end
