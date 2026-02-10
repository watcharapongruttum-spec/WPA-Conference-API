class ChatMessage < ApplicationRecord
  belongs_to :chat_room, optional: true
  belongs_to :sender, class_name: "Delegate"
  belongs_to :recipient,
             class_name: "Delegate",
             foreign_key: "recipient_id",
             optional: true

  validates :content, presence: true
  validate :can_send_message

  # after_create_commit :broadcast_create

  # -------------------
  # helpers
  # -------------------
  def edited?
    edited_at.present?
  end

  def deleted?
    deleted_at.present?
  end

  # -------------------
  private
  # -------------------

  def can_send_message
    return if chat_room.nil?
    unless chat_room.can_send_message?(sender)
      errors.add(:base, "Cannot send message")
    end
  end

  # def broadcast_create
  #   payload = {
  #     type: "message_created",
  #     id: id,
  #     room_id: chat_room_id,
  #     sender_id: sender_id,
  #     content: content,
  #     created_at: created_at.strftime("%H:%M")
  #   }

  #   if chat_room
  #     ChatRoomChannel.broadcast_to(chat_room, payload)
  #   else
  #     ChatChannel.broadcast_to(recipient, payload)
  #   end
  # end



end
