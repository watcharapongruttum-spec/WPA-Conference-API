# app/services/chat/read_service.rb
module Chat
  class ReadService
    # ================= READ ALL (API) =================
    def self.read_all(delegate)
      now = Time.current

      # ✅ Direct chat — mark ทั้ง read_at (backward compat) และ MessageRead
      direct_messages = ChatMessage
        .where(recipient_id: delegate.id, read_at: nil, deleted_at: nil)
        .where(chat_room_id: nil)

      direct_ids = direct_messages.pluck(:id)

      if direct_ids.any?
        direct_messages.update_all(read_at: now)
        _insert_message_reads(direct_ids, delegate.id, now)
      end

      # ✅ Group chat — mark ผ่าน MessageRead table
      group_room_ids = ChatRoomMember
                       .joins(:chat_room)
                       .where(delegate_id: delegate.id)
                       .where(chat_rooms: { deleted_at: nil })
                       .pluck(:chat_room_id)

      if group_room_ids.any?
        group_ids = ChatMessage
                    .where(chat_room_id: group_room_ids)
                    .where(deleted_at: nil)
                    .where.not(sender_id: delegate.id)
                    .where.not(
                      id: MessageRead.where(delegate_id: delegate.id).select(:chat_message_id)
                    )
                    .pluck(:id)

        _insert_message_reads(group_ids, delegate.id, now) if group_ids.any?
      end

      Rails.cache.delete("dashboard:#{delegate.id}:v1")
    end

    # ================= MARK ONE (direct chat) =================
    def self.mark_one(message)
      return if message.read_at.present?

      now = Time.current

      # ✅ sync ทั้ง read_at และ MessageRead
      message.update_column(:read_at, now)
      _insert_message_reads([message.id], message.recipient_id, now)

      payload = {
        type:       "message_read",
        message_id: message.id,
        read_at:    TimeFormatter.format(now)
      }

      ChatChannel.broadcast_to(message.sender,    payload)
      ChatChannel.broadcast_to(message.recipient, payload)
    end

    # ================= MARK ROOM (direct chat) =================
    # เรียกจาก ChatChannel#enter_room และ RoomStateService
    def self.mark_room(user_id, target_id)
      now = Time.current

      scope = ChatMessage
              .where(sender_id: target_id,
                     recipient_id: user_id,
                     read_at: nil,
                     chat_room_id: nil)

      ids = scope.pluck(:id)
      return if ids.empty?

      # ✅ sync ทั้ง read_at (backward compat) และ MessageRead
      scope.update_all(read_at: now)
      _insert_message_reads(ids, user_id, now)

      Rails.cache.delete("dashboard:#{user_id}:v1")

      payload = {
        type:        "bulk_read",
        message_ids: ids,
        read_at:     TimeFormatter.format(now)
      }

      user   = Delegate.find_by(id: user_id)
      target = Delegate.find_by(id: target_id)

      ChatChannel.broadcast_to(user,   payload) if user
      ChatChannel.broadcast_to(target, payload) if target
    end

    # ================= AUTO ON SUBSCRIBE (legacy) =================
    def self.mark_all_for_user(user_id)
      now = Time.current

      unread_messages = ChatMessage
                        .where(recipient_id: user_id, read_at: nil, chat_room_id: nil)

      ids = unread_messages.pluck(:id)
      return if ids.empty?

      unread_messages.update_all(read_at: now)
      _insert_message_reads(ids, user_id, now)

      sender_ids = ChatMessage
                   .where(id: ids)
                   .distinct
                   .pluck(:sender_id)

      payload = {
        type:        "bulk_read",
        message_ids: ids,
        read_at:     TimeFormatter.format(now)
      }

      Delegate.where(id: sender_ids).find_each do |delegate|
        ChatChannel.broadcast_to(delegate, payload)
      end
    end

    # ================= PRIVATE =================
    private_class_method def self._insert_message_reads(message_ids, delegate_id, now)
      return if message_ids.blank?

      rows = message_ids.map do |msg_id|
        {
          chat_message_id: msg_id,
          delegate_id:     delegate_id,
          read_at:         now,
          created_at:      now,
          updated_at:      now
        }
      end

      MessageRead.upsert_all(rows, unique_by: %i[chat_message_id delegate_id])
    rescue => e
      Rails.logger.error "[ReadService] upsert_all failed: #{e.message}"
    end
  end
end