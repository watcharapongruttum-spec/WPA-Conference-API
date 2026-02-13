module Chat
  class ReadService
    # ================= ONE =================
    def self.mark_one(message)
      return if message.read_at.present?

      now = Time.current
      message.update_column(:read_at, now)

      payload = {
        type: 'message_read',
        message_id: message.id,
        read_at: now
      }

      ChatChannel.broadcast_to(message.sender, payload)
      ChatChannel.broadcast_to(message.recipient, payload)
    end

    # ================= ROOM =================
    def self.mark_room(user_id, target_id)
      now = Time.current

      scope = ChatMessage.where(
        sender_id: target_id,
        recipient_id: user_id,
        read_at: nil,
        deleted_at: nil
      )

      ids = scope.pluck(:id)
      scope.update_all(read_at: now)

      return if ids.empty?

      payload = {
        type: 'bulk_read',
        message_ids: ids,
        read_at: now
      }

      user   = Delegate.find(user_id)
      target = Delegate.find(target_id)

      ChatChannel.broadcast_to(user, payload)
      ChatChannel.broadcast_to(target, payload)
    end

    # ================= ALL =================
    def self.read_all(user)
      now = Time.current

      messages = user.received_messages
        .where(read_at: nil, deleted_at: nil)

      ids = messages.pluck(:id, :sender_id)
      messages.update_all(read_at: now)

      ids.each do |msg_id, sender_id|
        ChatChannel.broadcast_to(
          Delegate.find(sender_id),
          type: 'message_read',
          message_id: msg_id,
          read_at: now
        )
      end
    end
  end
end
