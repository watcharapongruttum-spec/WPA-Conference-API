class ChatMessage < ApplicationRecord
  belongs_to :chat_room, optional: true
  belongs_to :sender, class_name: "Delegate"
  belongs_to :recipient,
             class_name: "Delegate",
             foreign_key: "recipient_id",
             optional: true

  # ==========================
  # CALLBACKS
  # ==========================
  before_validation :normalize_content

  # ==========================
  # VALIDATIONS
  # ==========================
  validates :content, presence: { message: "cannot be blank" }
  validates :content,
            length: {
              minimum: 1,
              maximum: 2000,
              message: "must be between 1 and 2000 characters"
            }

  validate :content_not_empty_after_strip
  validate :can_send_message
  validate :room_or_direct_present


  has_many :message_reads, dependent: :destroy

  # ==========================
  # SCOPES
  # ==========================
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

  # ==========================
  # HELPERS
  # ==========================
  def edited?
    edited_at.present?
  end

  def deleted?
    deleted_at.present?
  end

  def content_preview(length = 50)
    content.to_s.truncate(length)
  end

  private

  # ==========================
  # NORMALIZE
  # ==========================
  def normalize_content
    return if content.nil?
    self.content = content.strip
  end

  # ==========================
  # VALIDATIONS
  # ==========================
  def content_not_empty_after_strip
    if content.present? && content.strip.empty?
      errors.add(:content, "cannot be only whitespace")
    end
  end

  def can_send_message
    return if chat_room.nil?
    unless chat_room.can_send_message?(sender)
      errors.add(:base, "Cannot send message to this room")
    end
  end

  def room_or_direct_present
    if chat_room.nil? && recipient.nil?
      errors.add(:base, "Message must belong to a room or have a recipient")
    end

    if chat_room.present? && recipient.present?
      errors.add(:base, "Message cannot have both room and recipient")
    end
  end
end
