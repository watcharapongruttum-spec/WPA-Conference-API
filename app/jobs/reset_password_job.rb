class ResetPasswordJob < ApplicationJob
  queue_as :default

  def perform(delegate_id)
    delegate = Delegate.find_by(id: delegate_id)
    return unless delegate

    reset_url = "#{ENV['FRONTEND_URL']}/reset-password?token=#{delegate.reset_password_token}"

    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <body style="font-family: Arial, sans-serif; padding:20px;">
          <h2>Reset Your Password</h2>

          <p>You requested to reset your password.</p>

          <p>
            <a href="#{reset_url}"
              style="display:inline-block;
                     padding:12px 20px;
                     background:#4CAF50;
                     color:white;
                     text-decoration:none;
                     border-radius:6px;">
              Reset Password
            </a>
          </p>

          <p>If button doesn't work, use this token:</p>

          <div style="background:#f0f0f0; padding:10px;">
            #{delegate.reset_password_token}
          </div>
        </body>
      </html>
    HTML

    Rails.logger.info "HTML SIZE: #{html.length}"

    BrevoMailService.send_email(
      to: delegate.email,
      subject: "Reset Your Password",
      html: html
    )
  end
end
