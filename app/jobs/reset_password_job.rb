class ResetPasswordJob < ApplicationJob
  queue_as :default

  def perform(delegate_id)
    delegate = Delegate.find_by(id: delegate_id)
    return unless delegate

    reset_url = "#{ENV['FRONTEND_URL']}/reset-password?token=#{delegate.reset_password_token}"

    html = ApplicationController.render(
      template: "password_mailer/reset_password",
      assigns: {
        reset_url: reset_url,
        token: delegate.reset_password_token
      }
    )

    BrevoMailService.send_email(
      to: delegate.email,
      subject: "Reset Your Password",
      html: html
    )
  rescue => e
    Rails.logger.error "[ResetPasswordJob] Failed: #{e.message}"
  end
end
