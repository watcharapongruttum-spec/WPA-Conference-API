class NotificationChannel < ApplicationCable::Channel
  def subscribed
    # ใช้ current_delegate (object) แทน current_delegate.id
    stream_for current_delegate
    logger.info "✅ NotificationChannel subscribed: delegate #{current_delegate.id}"
  end

  def unsubscribed
    logger.info "⚠️ NotificationChannel unsubscribed: delegate #{current_delegate.id}"
  end
end
