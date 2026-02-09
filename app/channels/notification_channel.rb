class NotificationChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_delegate
    logger.info "✅ NotificationChannel subscribed: delegate #{current_delegate.id}"
  end

  def unsubscribed
    logger.info "⚠️ NotificationChannel unsubscribed: delegate #{current_delegate.id}"
  end
end
