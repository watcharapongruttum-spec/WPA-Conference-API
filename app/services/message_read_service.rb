class MessageReadService
  def self.mark_one(message)
    return if message.read_at.present?

    message.update_column(:read_at, Time.current)
  end

  def self.mark_room(user_id, target_id)
    ChatMessage
      .where(sender_id: target_id, recipient_id: user_id, read_at: nil)
      .update_all(read_at: Time.current)
  end
end
