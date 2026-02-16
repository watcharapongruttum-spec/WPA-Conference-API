module Api
  module V1
    class SessionsController < ApplicationController
      skip_before_action :authenticate_delegate!, only: [:create, :forgot_password, :reset_password]


      
      # POST /api/v1/login
      def create
        email = params[:email]&.strip
        password = params[:password]

        if email.blank? || password.blank?
          render json: { error: 'Email and password are required' }, status: :unprocessable_entity
          return
        end

        @delegate = Delegate.find_by(email: email)

        if @delegate.nil?
          render json: { error: 'Invalid credentials' }, status: :unauthorized
          return
        end

        if @delegate.authenticate(password)
          first_login = @delegate.first_login?

          token = @delegate.generate_jwt_token
          @delegate.mark_as_logged_in if first_login

          render json: {
            token: token,
            delegate: Api::V1::DelegateSerializer
                        .new(@delegate)
                        .serializable_hash,
            first_login: first_login
          }, status: :ok
        else
          render json: { error: 'Invalid credentials' }, status: :unauthorized
        end
      end



      
      # POST /api/v1/change_password
      def change_password
        @delegate = current_delegate

        if @delegate.nil?
          render json: { error: 'Authentication required' }, status: :unauthorized
          return
        end

       if @delegate.update(
          password: params[:new_password],
          password_confirmation: params[:new_password]
        )

          SecurityLog.create(
            delegate: @delegate,
            event: 'change_password',
            ip: request.remote_ip
          )

          render json: { message: 'Password changed successfully' }, status: :ok

        else
          render json: {
            error: 'Failed to change password',
            errors: @delegate.errors.full_messages
          }, status: :unprocessable_entity
        end
      end


  
      # POST /api/v1/forgot_password
      def forgot_password
        email = params[:email]&.strip
        return render json: { error: 'Email is required' }, status: :unprocessable_entity if email.blank?

        @delegate = Delegate.find_by(email: email)

        if @delegate
          # ===== RATE LIMIT =====
          if @delegate.reset_password_sent_at&.> 1.minute.ago
            return render json: { message: 'Please wait before retry' }, status: :ok
          end

          # ===== GENERATE TOKEN =====
          @delegate.generate_reset_token!

          # ===== SEND EMAIL =====
          # PasswordMailer.reset_password(@delegate).deliver_later

          PasswordMailer.reset_password(@delegate).deliver_now


          # ===== SECURITY LOG =====
          SecurityLog.create(
            delegate: @delegate,
            event: 'forgot_password',
            ip: request.remote_ip
          )
        end

        render json: {
          message: 'If the email exists, a password reset link will be sent'
        }, status: :ok
      end









      # POST /api/v1/reset_password
      def reset_password
        token = params[:token]
        password = params[:password]
        password_confirmation = params[:password_confirmation]

        return render json: { error: 'Token required' }, status: 422 if token.blank?

        @delegate = Delegate.find_by(reset_password_token: token)
        return render json: { error: 'Invalid token' }, status: 422 unless @delegate

        # ===== TOKEN EXPIRE =====
        unless @delegate.reset_token_valid?
          return render json: { error: 'Token expired' }, status: 422
        end

        # ===== CONFIRM PASSWORD =====
        if password != password_confirmation
          return render json: { error: 'Password mismatch' }, status: 422
        end

        @delegate.password = password
        @delegate.save!

        @delegate.clear_reset_token!

        SecurityLog.create(
          delegate: @delegate,
          event: 'reset_password_success',
          ip: request.remote_ip
        )

        render json: { message: 'Password updated' }
      end






    end
  end
end
