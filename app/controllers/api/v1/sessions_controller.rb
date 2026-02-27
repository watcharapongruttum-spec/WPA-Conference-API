module Api
  module V1
    class SessionsController < ApplicationController
      skip_before_action :authenticate_delegate!,
                         only: %i[create forgot_password reset_password]

      # ============================================
      # POST /api/v1/login
      # ============================================
      def create
        email = params[:email]&.strip&.downcase
        password = params[:password]

        if email.blank? || password.blank?
          return render json: { error: "Email and password are required" },
                        status: :unprocessable_entity
        end

        @delegate = Delegate.find_by(email: email)

        unless @delegate&.authenticate(password)
          if defined?(AuditLogger)
            AuditLogger.login(
              email: email,
              delegate: nil,
              request: request,
              metadata: request_metadata,
              success: false
            )
          end

          return render json: { error: "Invalid credentials" },
                        status: :unauthorized
        end

        first_login = @delegate.first_login?
        token = @delegate.generate_jwt_token

        ActiveRecord::Base.transaction do
          @delegate.mark_as_logged_in if first_login

          SecurityLog.create!(
            delegate: @delegate,
            event: "login",
            ip: request.remote_ip
          )

          if defined?(AuditLogger)
            AuditLogger.login(
              delegate: @delegate,
              email: @delegate.email,
              request: request,
              metadata: request_metadata,
              success: true
            )
          end
        end

        render json: {
          token: token,
          delegate: Api::V1::DelegateSerializer
                    .new(@delegate)
                    .serializable_hash,
          first_login: first_login
        }, status: :ok
      end

      # ============================================
      # POST /api/v1/change_password
      # ============================================
      def change_password
        p = password_params

        unless p[:new_password].present? && p[:new_password_confirmation].present?
          return render json: { error: "New password and confirmation required" },
                        status: :unprocessable_entity
        end

        unless current_delegate.authenticate(p[:current_password])
          AuditLogger.password_change(
            delegate: current_delegate,
            request: request,
            success: false
          )
          return render json: { error: "Current password incorrect" },
                        status: :unauthorized
        end

        if p[:new_password] != p[:new_password_confirmation]
          AuditLogger.password_change(
            delegate: current_delegate,
            request: request,
            success: false
          )
          return render json: { error: "Password confirmation mismatch" },
                        status: :unprocessable_entity
        end

        # 🔴 เพิ่ม: ตรวจสอบความแข็งแกร่งของรหัสผ่านใหม่
        error = validate_password_strength(p[:new_password])
        if error
          AuditLogger.password_change(
            delegate: current_delegate,
            request: request,
            success: false
          )
          return render json: { error: error }, status: :unprocessable_entity
        end

        if current_delegate.update(password: p[:new_password])
          AuditLogger.password_change(
            delegate: current_delegate,
            request: request,
            success: true
          )
          render json: { message: "Password changed successfully" }
        else
          render json: { error: current_delegate.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      # ============================================
      # POST /api/v1/forgot_password
      # ============================================
      def forgot_password
        email = params[:email]&.strip&.downcase

        if email.blank?
          return render json: { error: "Email is required" },
                        status: :unprocessable_entity
        end

        @delegate = Delegate.find_by(email: email)

        if @delegate
          if @delegate.reset_password_sent_at&.> 1.minute.ago
            return render json: { message: "Please wait before retry" },
                          status: :ok
          end

          ActiveRecord::Base.transaction do
            @delegate.generate_reset_token!

            SecurityLog.create!(
              delegate: @delegate,
              event: "forgot_password",
              ip: request.remote_ip
            )

            if defined?(AuditLogger)
              AuditLogger.password_reset_request(
                delegate: @delegate,
                request: request
              )
            end
          end

          ResetPasswordJob.perform_later(@delegate.id)
        end

        render json: {
          message: "If the email exists, a password reset link will be sent"
        }, status: :ok
      end

      # ============================================
      # POST /api/v1/reset_password
      # ============================================
      def reset_password
        token = params[:token]
        password = params[:password]
        password_confirmation = params[:password_confirmation]

        if token.blank?
          return render json: { error: "Token required" },
                        status: :unprocessable_entity
        end

        @delegate = Delegate.find_by(reset_password_token: token)

        unless @delegate
          log_reset_failure(nil)
          return render json: { error: "Invalid token" },
                        status: :unprocessable_entity
        end

        unless @delegate.reset_token_valid?
          log_reset_failure(@delegate)
          return render json: { error: "Token expired" },
                        status: :unprocessable_entity
        end

        unless password == password_confirmation
          log_reset_failure(@delegate)
          return render json: { error: "Password mismatch" },
                        status: :unprocessable_entity
        end

        # 🔴 เพิ่ม: ตรวจสอบความแข็งแกร่งของรหัสผ่านใหม่
        error = validate_password_strength(password)
        if error
          log_reset_failure(@delegate)
          return render json: { error: error }, status: :unprocessable_entity
        end

        ActiveRecord::Base.transaction do
          @delegate.update!(
            password: password,
            password_confirmation: password
          )

          @delegate.clear_reset_token!

          SecurityLog.create!(
            delegate: @delegate,
            event: "reset_password_success",
            ip: request.remote_ip
          )

          if defined?(AuditLogger)
            AuditLogger.password_reset(
              delegate: @delegate,
              request: request,
              success: true
            )
          end
        end

        render json: { message: "Password updated" }
      rescue ActiveRecord::RecordInvalid => e
        log_reset_failure(@delegate)
        render json: { error: e.message },
               status: :unprocessable_entity
      end

      private

      # ============================================
      # 🔴 เพิ่ม: Password Strength Validator
      # คืน error message ถ้า invalid, nil ถ้า valid
      # ============================================
      def validate_password_strength(password)
        return "Password must be at least 8 characters" if password.length < 8
        return "Password must contain at least one number" unless password.match?(/[0-9]/)

        nil
      end

      def request_metadata
        {
          ip: request.remote_ip,
          user_agent: request.user_agent,
          request_id: request.request_id,
          timestamp: Time.current
        }
      end

      def password_params
        if params[:session]
          params.require(:session)
                .permit(:current_password, :new_password, :new_password_confirmation)
        else
          params.permit(:current_password, :new_password, :new_password_confirmation)
        end
      end

      def log_reset_failure(delegate)
        AuditLogger.password_reset(
          delegate: delegate,
          request: request,
          success: false
        )
      end
    end
  end
end
