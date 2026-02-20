# class PasswordMailer < ApplicationMailer
#   default from: ENV["MAIL_USER"]

#   def reset_password(delegate)
#     @delegate = delegate
#     @token = delegate.reset_password_token

#     @reset_url = "#{ENV['FRONTEND_URL']}/reset-password?token=#{@token}"

#     mail(to: @delegate.email, subject: 'Reset your password')
#   end

# end




class PasswordMailer < ApplicationMailer
  def reset_password(delegate)
    @delegate = delegate
    @token = delegate.reset_password_token
    @reset_url = "#{ENV['FRONTEND_URL']}/reset-password?token=#{@token}"

    html = ApplicationController.render(
      template: "password_mailer/reset_password",
      assigns: { delegate: @delegate, token: @token, reset_url: @reset_url }
    )

    BrevoMailService.send_email(
      to: @delegate.email,
      subject: "Reset your password",
      html: html
    )
  end
end


