module Api
  module V1
    class SessionsController < ApplicationController
      skip_before_action :authenticate_delegate!, only: [:create, :forgot_password]

      
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

        if email.blank?
          render json: { error: 'Email is required' }, status: :unprocessable_entity
          return
        end

        @delegate = Delegate.find_by(email: email)

        # ไม่บอกว่า email มีหรือไม่
        if @delegate.nil?
          render json: {
            message: 'If the email exists, a password reset link will be sent'
          }, status: :ok
          return
        end

        temp_password = @delegate.generate_temporary_password(overwrite: true)

        # TODO: ส่งอีเมล
        # DelegateMailer.password_reset(@delegate, temp_password).deliver_now

        render json: {
          message: 'Temporary password has been generated and sent to your email'
        }, status: :ok
      end
    end
  end
end
