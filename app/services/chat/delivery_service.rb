module Chat
  class DeliveryService
    # ===== ONE =====
    def self.mark_one(message)
      return if message.delivered_at.present?

      message.update_column(:delivered_at, Time.current)
    end

    # ===== USER ONLINE =====
    def self.mark_user_online(user_id)
      ChatMessage.where(
        recipient_id: user_id,
        delivered_at: nil,
        deleted_at: nil
      ).update_all(delivered_at: Time.current)
    end

    # ===== ROOM OPEN =====
    def self.mark_room(user_id, target_id)
      ChatMessage.where(
        sender_id: target_id,
        recipient_id: user_id,
        delivered_at: nil,
        deleted_at: nil
      ).update_all(delivered_at: Time.current)
    end
  end
end
