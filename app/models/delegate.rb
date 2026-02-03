class Delegate < ApplicationRecord
  has_secure_password

  # ========================
  # Associations
  # ========================

  belongs_to :company
  belongs_to :team, optional: true

  # ------------------------
  # Schedules
  # ------------------------
  has_many :booked_schedules,
           class_name: 'Schedule',
           foreign_key: 'booker_id',
           dependent: :destroy

  has_many :targeted_schedules,
           class_name: 'Schedule',
           foreign_key: 'target_id',
           dependent: :destroy

  # ------------------------
  # Notifications
  # ------------------------
  has_many :notifications, dependent: :destroy

  # ------------------------
  # Connections
  # ------------------------
  has_many :connection_requests_as_requester,
           class_name: 'ConnectionRequest',
           foreign_key: 'requester_id',
           dependent: :destroy

  has_many :connection_requests_as_target,
           class_name: 'ConnectionRequest',
           foreign_key: 'target_id',
           dependent: :destroy

  # ------------------------
  # Chat
  # ------------------------
  has_many :chat_room_members, dependent: :destroy
  has_many :chat_rooms, through: :chat_room_members

  has_many :sent_messages,
           class_name: 'ChatMessage',
           foreign_key: :sender_id,
           dependent: :destroy

  has_many :received_messages,
           class_name: 'ChatMessage',
           foreign_key: :recipient_id,
           dependent: :destroy

  # ------------------------
  # Attachments
  # ------------------------
  has_one_attached :avatar

  # ------------------------
  # Delegates
  # ------------------------
  delegate :name, to: :company, prefix: true

  # ========================
  # Login helpers
  # ========================
  def first_login?
    !has_logged_in
  end

  def mark_as_logged_in
    return if has_logged_in

    update!(
      has_logged_in: true,
      first_login_at: Time.current
    )
  end

  # ========================
  # JWT
  # ========================
  def generate_jwt_token
    payload = {
      delegate_id: id,
      iss: JWT_CONFIG[:issuer],
      exp: Time.now.to_i + JWT_CONFIG[:expiration_time]
    }

    JWT.encode(
      payload,
      JWT_SECRET,
      JWT_CONFIG[:algorithm]
    )
  end

  # ========================
  # Password reset
  # ========================
  def generate_temporary_password(overwrite: false)
    return nil if password_digest.present? && !overwrite

    temp_password = SecureRandom.alphanumeric(10)

    self.password = temp_password
    self.has_logged_in = false
    self.first_login_at = nil
    save!(validate: false)

    temp_password
  end

  # ========================
  # Connections helpers
  # ========================
  def connected_delegates
    ConnectionRequest.accepted
      .where(requester: self)
      .or(ConnectionRequest.accepted.where(target: self))
      .map { |c| c.requester == self ? c.target : c.requester }
  end
end
