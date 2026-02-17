class PasswordMailer < ApplicationMailer
  default from: ENV["MAIL_USER"]

  def reset_password(delegate)
    @delegate = delegate
    @token = delegate.reset_password_token

    @reset_url = "#{ENV['FRONTEND_URL']}/reset-password?token=#{@token}"

    mail(to: @delegate.email, subject: 'Reset your password')
  end

end
