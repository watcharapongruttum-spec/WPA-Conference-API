# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
  include ActionController::Serialization

  # ==============================
  # Specific Errors (TOP FIRST)
  # ==============================

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from ActionController::ParameterMissing, with: :missing_params
  rescue_from ActiveRecord::RecordInvalid, with: :record_invalid

  # 🔐 Catch ALL JWT errors safely
  rescue_from JWT::DecodeError, with: :invalid_token
  rescue_from JWT::VerificationError, with: :invalid_token
  rescue_from JWT::ExpiredSignature, with: :invalid_token
  rescue_from JWT::InvalidIssuerError, with: :invalid_token

  # ==============================
  # Catch unexpected LAST
  # ==============================
  # rescue_from StandardError, with: :handle_unexpected_error
  rescue_from StandardError, with: :handle_unexpected_error if Rails.env.production?

  before_action :set_active_storage_host
  before_action :authenticate_delegate!

  private

  # ==============================
  # Error Handlers
  # ==============================

  def record_not_found(_exception = nil)
    render json: { error: "Record not found" }, status: :not_found
  end

  def missing_params(exception)
    render json: {
      error: "Missing parameter: #{exception.param}"
    }, status: :unprocessable_entity # เปลี่ยนจาก :bad_request
  end

  def record_invalid(exception)
    render json: {
      error: "Validation failed",
      messages: exception.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  def invalid_token(_exception = nil)
    render json: { error: "Invalid or expired token" }, status: :unauthorized
  end

  def handle_unexpected_error(exception)
    Rails.logger.error "Unexpected Error: #{exception.class}"
    Rails.logger.error exception.message
    Rails.logger.error exception.backtrace.first(10).join("\n")

    render json: {
      error: "An unexpected error occurred",
      message: Rails.env.development? ? exception.message : nil
    }, status: :internal_server_error
  end

  # ==============================
  # Authentication
  # ==============================

  def current_delegate
    return @current_delegate if defined?(@current_delegate)

    @current_delegate = authenticate_from_token
  end













  def authenticate_from_token
    token = request.headers["Authorization"]&.split&.last
    return nil if token.blank?

    payload = JwtDecoder.decode!(token)
    delegate = Delegate.find_by(id: payload["delegate_id"])
    return nil unless delegate

    # ✅ เช็ค version ตรงกับใน DB ไหม
    return nil if payload["token_version"] != delegate.token_version

    delegate
  rescue JWT::DecodeError,
        JWT::ExpiredSignature,
        JWT::VerificationError,
        JWT::InvalidIssuerError => e
    Rails.logger.warn "JWT Error: #{e.class} - #{e.message}"
    nil
  end



















  def authenticate_delegate!
    return if current_delegate

    render json: { error: "Invalid or expired token" }, status: :unauthorized
  end

  def set_active_storage_host
    ActiveStorage::Current.url_options = {
      host: request.base_url
    }
  end
end
