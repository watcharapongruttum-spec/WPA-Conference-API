class Delegate < ApplicationRecord
  has_secure_password

  # validates :password, length: { minimum: 6 }, allow_nil: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  before_save :sanitize_fields

  validates :device_token,
            length: { minimum: 20, maximum: 255 },
            # format: { with: /\A[\w\-\:]+\z/ },
            # format: { with: %r{\A[\w\-:/]+\z} },
            format: { with: /\AExponentPushToken\[.{10,}\]\z|\A[a-zA-Z0-9_\-]{100,}\z|\A[a-zA-Z0-9_\-]+:[a-zA-Z0-9_\-]+\z/, message: "is invalid" },
            allow_nil: true

  # ========================
  # Associations
  # ========================

  belongs_to :company
  belongs_to :team, optional: true

  # ------------------------
  # Schedules
  # ------------------------
  has_many :booked_schedules,
           class_name: "Schedule",
           foreign_key: "booker_id",
           dependent: :destroy

  has_many :targeted_schedules,
           class_name: "Schedule",
           foreign_key: "target_id",
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
           class_name: "ConnectionRequest",
           foreign_key: "requester_id",
           dependent: :destroy

  has_many :connection_requests_as_target,
           class_name: "ConnectionRequest",
           foreign_key: "target_id",
           dependent: :destroy

  # ------------------------
  # Chat
  # ------------------------
  has_many :chat_room_members, dependent: :destroy
  has_many :chat_rooms, through: :chat_room_members

  has_many :sent_messages,
           class_name: "ChatMessage",
           foreign_key: :sender_id,
           dependent: :destroy

  has_many :received_messages,
           class_name: "ChatMessage",
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
      token_version: token_version,
      exp: JWT_CONFIG[:expiration_time].from_now.to_i,
      iss: JWT_CONFIG[:issuer]
    }

    JWT.encode(payload, JWT_CONFIG[:secret], JWT_CONFIG[:algorithm])
  end





  def invalidate_all_tokens!
    increment!(:token_version)
  end







  # ========================
  # Password reset
  # ========================

  def reset_token_valid?
    # reset_password_sent_at && reset_password_sent_at > 15.minutes.ago
    reset_password_sent_at && reset_password_sent_at > 30.minutes.ago
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

  # ========================
  # Temporary Password
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
                     .includes(:requester, :target)
                     .map { |c| c.requester == self ? c.target : c.requester }
  end

  # ========================
  # Avatar
  # ========================

  # ✅ แก้แล้ว — fallback ui-avatars อัตโนมัติ
  # def avatar_url
  #   if avatar.attached?
  #     Rails.application.routes.url_helpers.rails_blob_url(
  #       avatar,
  #       only_path: true
  #     )
  #   else
  #     ui_avatar_url
  #   end
  # end

  def avatar_url
    if avatar.attached?
      path = Rails.application.routes.url_helpers.rails_blob_path(
        avatar, only_path: true
      )

      host     = ENV.fetch("APP_HOST", "localhost:3000")
      protocol = host.include?("localhost") ? "http" : "https"

      "#{protocol}://#{host}#{path}"
    else
      ui_avatar_url
    end
  end

  def ui_avatar_url
    "https://ui-avatars.com/api/?name=#{CGI.escape(name.presence || 'Unknown')}&background=0D8ABC&color=fff"
  end

  def connection_status_with(me)
    return "none" if me.nil? || me.id == id

    connection = ConnectionRequest
                 .where(
                   "(requester_id = :me AND target_id = :other)
                      OR (requester_id = :other AND target_id = :me)",
                   me: me.id,
                   other: id
                 )
                 .order(created_at: :desc)
                 .first

    return "none" unless connection

    case connection.status
    when "accepted"
      "connected"
    when "pending"
      connection.requester_id == me.id ? "requested_by_me" : "requested_to_me"
    else
      "none"
    end
  end

  def connection_request_id_with(me)
    return nil if me.nil? || me.id == id
    ConnectionRequest
      .where(
        "(requester_id = :me AND target_id = :other)
          OR (requester_id = :other AND target_id = :me)",
        me: me.id,
        other: id
      )
      .where(status: :pending)
      .order(created_at: :desc)
      .first&.id
  end



  private

def sanitize_fields
  self.name  = strip_tags(name.to_s)
  self.title = strip_tags(title.to_s)
  self.phone = strip_tags(phone.to_s)
end

def strip_tags(str)
  ActionController::Base.helpers.sanitize(str, tags: [])
end






end
