module Chat
  class ReadService
    # ================= READ ALL (API) =================
    def self.read_all(delegate)
      now = Time.current

      # ✅ แชท 1-1 — ใช้ read_at บน chat_messages (ถูกต้อง)
      ChatMessage
        .where(recipient_id: delegate.id, read_at: nil, deleted_at: nil)
        .update_all(read_at: now)

      # ✅ FIX: Group chat — mark ผ่าน MessageRead table
      # เดิมใช้ update_all read_at บน chat_messages ซึ่งไม่มีผลต่อ unread count จริง
      group_room_ids = ChatRoomMember
                       .joins(:chat_room)
                       .where(delegate_id: delegate.id)
                       .where(chat_rooms: { deleted_at: nil })
                       .pluck(:chat_room_id)

      if group_room_ids.any?
        unread_message_ids = ChatMessage
                             .where(chat_room_id: group_room_ids)
                             .where(deleted_at: nil)
                             .where.not(sender_id: delegate.id)
                             .where.not(
                               id: MessageRead.where(delegate_id: delegate.id).select(:chat_message_id)
                             )
                             .pluck(:id)

        if unread_message_ids.any?
          rows = unread_message_ids.map do |msg_id|
            {
              chat_message_id: msg_id,
              delegate_id: delegate.id,
              read_at: now,
              created_at: now,
              updated_at: now
            }
          end

          MessageRead.upsert_all(rows, unique_by: %i[chat_message_id delegate_id])
        end
      end

      # ✅ Clear dashboard cache หลัง mark read
      Rails.cache.delete("dashboard:#{delegate.id}:v1")
    end

    # ================= MARK ONE =================
    def self.mark_one(message)
      return if message.read_at.present?

      now = Time.current
      message.update_column(:read_at, now)

      payload = {
        type: "message_read",
        message_id: message.id,
        read_at: now
      }

      ChatChannel.broadcast_to(message.sender,    payload)
      ChatChannel.broadcast_to(message.recipient, payload)
    end

    # ================= MARK ROOM (direct chat) =================
    def self.mark_room(user_id, target_id)
      now = Time.current

      scope = ChatMessage
              .where(sender_id: target_id,
                     recipient_id: user_id,
                     read_at: nil)

      ids = scope.pluck(:id)
      scope.update_all(read_at: now)

      return if ids.empty?

      payload = {
        type: "bulk_read",
        message_ids: ids,
        read_at: now
      }

      user   = Delegate.find(user_id)
      target = Delegate.find(target_id)

      ChatChannel.broadcast_to(user,   payload)
      ChatChannel.broadcast_to(target, payload)
    end

    # ================= AUTO ON SUBSCRIBE =================
    def self.mark_all_for_user(user_id)
      now = Time.current

      # ดึง unread messages ของ user
      unread_messages = ChatMessage
                        .where(recipient_id: user_id, read_at: nil)

      ids = unread_messages.pluck(:id)
      return if ids.empty?

      # update ทีเดียว
      unread_messages.update_all(read_at: now)

      # หา sender ทั้งหมดทีเดียว (ไม่ query ซ้ำ)
      sender_ids = ChatMessage
                   .where(id: ids)
                   .distinct
                   .pluck(:sender_id)

      payload = {
        type: "bulk_read",
        message_ids: ids,
        read_at: now
      }

      # preload delegates ทีเดียว
      Delegate.where(id: sender_ids).find_each do |delegate|
        ChatChannel.broadcast_to(delegate, payload)
      end
    end
  end
end
