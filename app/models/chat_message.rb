class ChatMessage < ApplicationRecord
  belongs_to :chat_room, optional: true
  belongs_to :sender, class_name: "Delegate"
  belongs_to :recipient,
             class_name: "Delegate",
             foreign_key: "recipient_id",
             optional: true

  # ==========================
  # ACTIVE STORAGE
  # ==========================
  has_one_attached :image

  # ==========================
  # CALLBACKS
  # ==========================
  before_validation :normalize_content

  # ==========================
  # VALIDATIONS
  # ==========================
  validates :content,
            presence: { message: "cannot be blank" },
            unless: :image?

  validates :content,
            length: { maximum: 2000, message: "must be between 1 and 2000 characters" },
            allow_blank: true

  validates :message_type,
            inclusion: { in: %w[text image] }

  validate :can_send_message
  validate :room_or_direct_present

  has_many :message_reads, dependent: :destroy

  # ==========================
  # SCOPES
  # ==========================
  scope :not_deleted, -> { where(deleted_at: nil) }

  scope :unread_between, lambda { |sender_id, recipient_id|
    where(
      sender_id: sender_id,
      recipient_id: recipient_id,
      read_at: nil,
      deleted_at: nil
    )
  }

  scope :undelivered_for, lambda { |recipient_id|
    where(
      recipient_id: recipient_id,
      delivered_at: nil,
      deleted_at: nil
    )
  }

  # ==========================
  # HELPERS
  # ==========================
  def image?
    message_type == "image"
  end

  def text?
    message_type == "text"
  end

  def edited?
    edited_at.present?
  end

  def deleted?
    deleted_at.present?
  end

  def content_preview(length = 50)
    return "📷 รูปภาพ" if image?
    content.to_s.truncate(length)
  end

  # ✅ FIX: ใช้ rails_blob_path + ENV host แบบเดียวกับ Delegate#avatar_url
  # แทน rails_blob_url ที่ต้องการ default_url_options[:host] ซึ่งอาจไม่ถูก set ใน ActionCable context
  def image_url
    return nil unless image.attached?

    path     = Rails.application.routes.url_helpers.rails_blob_path(image, only_path: true)
    host     = ENV.fetch("APP_HOST", "localhost:3000")
    protocol = host.include?("localhost") ? "http" : "https"

    "#{protocol}://#{host}#{path}"
  end

  private

  def normalize_content
    return if content.nil?
    self.content = content.strip
  end

  def can_send_message
    return if chat_room.nil?
    return if chat_room.can_send_message?(sender)
    errors.add(:base, "Cannot send message to this room")
  end

  def room_or_direct_present
    errors.add(:base, "Message must belong to a room or have a recipient") if chat_room.nil? && recipient.nil?
    return unless chat_room.present? && recipient.present?
    errors.add(:base, "Message cannot have both room and recipient")
  end
end