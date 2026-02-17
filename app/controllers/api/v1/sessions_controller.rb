module Api
  module V1
    class SessionsController < ApplicationController
      skip_before_action :authenticate_delegate!, only: [:create, :forgot_password, :reset_password]


      
      # POST /api/v1/login
      def create
        email = params[:email]&.strip&.downcase
        password = params[:password]

        return render json: { error: 'Email and password are required' }, status: :unprocessable_entity if email.blank? || password.blank?

        @delegate = Delegate.find_by(email: email)

        # ป้องกัน timing attack
        unless @delegate&.authenticate(password)
          AuditLogger.login(email, request) if defined?(AuditLogger)
          return render json: { error: 'Invalid credentials' }, status: :unauthorized
        end

        first_login = @delegate.first_login?

        token = @delegate.generate_jwt_token

        ActiveRecord::Base.transaction do
          @delegate.mark_as_logged_in if first_login

          SecurityLog.create!(
            delegate: @delegate,
            event: 'login',
            ip: request.remote_ip
          )

          AuditLogger.login(@delegate, request) if defined?(AuditLogger)
        end

        render json: {
          token: token,
          delegate: Api::V1::DelegateSerializer
                      .new(@delegate)
                      .serializable_hash,
          first_login: first_login
        }, status: :ok
      end



      
      # POST /api/v1/change_password
      def change_password
        @delegate = current_delegate
        unless @delegate
          render json: { error: 'Authentication required' }, status: :unauthorized
          return
        end
        
        # ⭐ Validate ให้ชัด
        if params[:new_password].blank? || params[:password_confirmation].blank?
          render json: { error: 'New password and confirmation required' }, status: :unprocessable_entity
          return
        end
        
        if params[:new_password] != params[:password_confirmation]
          render json: { error: 'Password confirmation does not match' }, status: :unprocessable_entity
          return
        end
        
        if @delegate.update(password: params[:new_password], password_confirmation: params[:password_confirmation])
          SecurityLog.create(delegate: @delegate, event: 'change_password', ip: request.remote_ip)
          AuditLogger.password_change(@delegate, request) if defined?(AuditLogger)
          render json: { message: 'Password changed successfully' }, status: :ok
        else
          render json: { error: 'Failed to change password', errors: @delegate.errors.full_messages }, status: :unprocessable_entity
        end
      end

        
      # POST /api/v1/forgot_password
      def forgot_password
        email = params[:email]&.strip&.downcase
        return render json: { error: 'Email is required' }, status: :unprocessable_entity if email.blank?

        @delegate = Delegate.find_by(email: email)

        if @delegate
          if @delegate.reset_password_sent_at&.> 1.minute.ago
            return render json: { message: 'Please wait before retry' }, status: :ok
          end

          ActiveRecord::Base.transaction do
            @delegate.generate_reset_token!

            PasswordMailer.reset_password(@delegate).deliver_later

            SecurityLog.create!(
              delegate: @delegate,
              event: 'forgot_password',
              ip: request.remote_ip
            )

            AuditLogger.password_reset(@delegate, request) if defined?(AuditLogger)
          end
        end

        # ป้องกัน email enumeration
        render json: {
          message: 'If the email exists, a password reset link will be sent'
        }, status: :ok
      end




      # POST /api/v1/reset_password
      def reset_password
        token = params[:token]
        password = params[:password]
        password_confirmation = params[:password_confirmation]

        return render json: { error: 'Token required' }, status: :unprocessable_entity if token.blank?

        @delegate = Delegate.find_by(reset_password_token: token)
        return render json: { error: 'Invalid token' }, status: :unprocessable_entity unless @delegate

        return render json: { error: 'Token expired' }, status: :unprocessable_entity unless @delegate.reset_token_valid?

        return render json: { error: 'Password mismatch' }, status: :unprocessable_entity unless password == password_confirmation

        return render json: { error: 'Password must be at least 8 characters' }, status: :unprocessable_entity if password.length < 8

        ActiveRecord::Base.transaction do
          @delegate.update!(
            password: password,
            password_confirmation: password
          )

          @delegate.clear_reset_token!

          SecurityLog.create!(
            delegate: @delegate,
            event: 'reset_password_success',
            ip: request.remote_ip
          )

          AuditLogger.password_reset(@delegate, request) if defined?(AuditLogger)
        end

        render json: { message: 'Password updated' }

      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end




    end
  end
end
