class ResetPasswordJob < ApplicationJob
  queue_as :default

  def perform(delegate_id)
    delegate = Delegate.find_by(id: delegate_id)
    return unless delegate

    PasswordMailer.reset_password(delegate)

  rescue => e
    Rails.logger.error "[ResetPasswordJob] Failed: #{e.message}"
  end
end
