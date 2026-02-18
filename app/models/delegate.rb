class Delegate < ApplicationRecord
  has_secure_password
  
  validates :password, length: { minimum: 6 }, allow_nil: true
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

  has_many :schedules

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
  # Deep Reset Password
  # ========================
  def generate_reset_token!
    self.reset_password_token = SecureRandom.hex(20)
    self.reset_password_sent_at = Time.current
    save!(validate: false)
  end

  def reset_token_valid?
    reset_password_sent_at && reset_password_sent_at > 2.hours.ago
  end

  def clear_reset_token!
    update_columns(
      reset_password_token: nil,
      reset_password_sent_at: nil
    )
  end








  # ========================
  # JWT
  # ========================
  # def generate_jwt_token
  #   payload = {
  #     delegate_id: id,
  #     iss: JWT_CONFIG[:issuer],
  #     exp: Time.now.to_i + JWT_CONFIG[:expiration_time]
  #   }

  #   JWT.encode(
  #     payload,
  #     JWT_SECRET,
  #     JWT_CONFIG[:algorithm]
  #   )
  # end

  def generate_jwt_token
    payload = {
      delegate_id: id,
      exp: JWT_CONFIG[:expiration_time].from_now.to_i,
      iss: JWT_CONFIG[:issuer]
    }

    JWT.encode(payload, JWT_CONFIG[:secret], JWT_CONFIG[:algorithm])
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







  def avatar_url
    if avatar_file_name.present?
      # ถ้าใช้ paperclip / active storage ก็ปรับตามจริง
      avatar.url
    else
      "https://ui-avatars.com/api/?name=#{CGI.escape(name)}&background=0D8ABC&color=fff"
    end
  end






    # =========================
    # RESET PASSWORD METHODS
    # =========================

    def reset_token_valid?
      reset_password_sent_at && reset_password_sent_at > 15.minutes.ago
    end

    def generate_reset_token!
      update!(
        reset_password_token: SecureRandom.hex(20),
        reset_password_sent_at: Time.current
      )
    end

    def clear_reset_token!
      update!(
        reset_password_token: nil,
        reset_password_sent_at: nil
      )
    end



end
