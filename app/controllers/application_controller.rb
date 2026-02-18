# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
  include ActionController::Serialization

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from ActionController::ParameterMissing, with: :missing_params
  rescue_from StandardError, with: :handle_unexpected_error

  before_action :authenticate_delegate!

  private

  def record_not_found
    render json: { error: 'Record not found' }, status: :not_found
  end

  def missing_params(exception)
    render json: { error: "Missing parameter: #{exception.param}" }, status: :bad_request
  end

  def handle_unexpected_error(exception)
    Rails.logger.error "Unexpected Error: #{exception.class}"
    Rails.logger.error exception.message
    Rails.logger.error exception.backtrace.first(10).join("\n")
    
    render json: { 
      error: 'An unexpected error occurred',
      message: Rails.env.development? ? exception.message : nil
    }, status: :internal_server_error
  end

  def current_delegate
    @current_delegate ||= begin
      token = request.headers['Authorization']&.split(' ')&.last
      return nil if token.blank?

      begin
        # decoded = JWT.decode(token, JWT_SECRET, true, algorithm: JWT_CONFIG[:algorithm])
        decoded = JWT.decode(
          token,
          JWT_CONFIG[:secret],
          true,
          algorithm: JWT_CONFIG[:algorithm]
        )

        delegate_id = decoded[0]['delegate_id']
        Delegate.find(delegate_id)
      rescue JWT::DecodeError, JWT::ExpiredSignature => e
        Rails.logger.warn "JWT Error: #{e.message}"
        nil
      rescue ActiveRecord::RecordNotFound => e
        Rails.logger.warn "Delegate not found: #{e.message}"
        nil
      end
    end
  end

  def authenticate_delegate!
    unless current_delegate
      render json: { error: 'Authentication required' }, status: :unauthorized
      return false
    end
    true
  end
end