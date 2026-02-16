class PasswordMailer < ApplicationMailer
  default from: ENV["MAIL_USER"]

  def reset_password(delegate)
    @delegate = delegate
    @token = delegate.reset_password_token

    # ===== WEB =====
    @web_url = "https://wpa-docker.onrender.com/reset-password?token=#{@token}"

    # ===== MOBILE DEEP LINK =====
    @app_url = "myapp://reset-password?token=#{@token}"

    mail(to: @delegate.email, subject: 'Reset your password')
  end
end
