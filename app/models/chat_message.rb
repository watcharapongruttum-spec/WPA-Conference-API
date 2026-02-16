class ChatMessage < ApplicationRecord
  belongs_to :chat_room, optional: true
  belongs_to :sender, class_name: "Delegate"
  belongs_to :recipient,
             class_name: "Delegate",
             foreign_key: "recipient_id",
             optional: true

  validates :content, presence: true
  validate :can_send_message

  # ================= SCOPES =================
  scope :not_deleted, -> { where(deleted_at: nil) }

  scope :unread_between, ->(sender_id, recipient_id) {
    where(
      sender_id: sender_id,
      recipient_id: recipient_id,
      read_at: nil,
      deleted_at: nil
    )
  }

  scope :undelivered_for, ->(recipient_id) {
    where(
      recipient_id: recipient_id,
      delivered_at: nil,
      deleted_at: nil
    )
  }

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
end
