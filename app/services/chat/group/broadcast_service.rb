# app/services/chat/group/broadcast_service.rb
#
# Single source of truth สำหรับทุก GroupChatChannel.broadcast_to
# ทุก event ที่ส่งหา frontend ต้องผ่านที่นี่เท่านั้น
#
# ใช้แทน GroupChatChannel.broadcast_to(...) ที่กระจายอยู่ใน:
#   - app/channels/group_chat_channel.rb
#   - app/controllers/api/v1/chat_rooms_controller.rb
#   - app/controllers/api/v1/group_chat_controller.rb
#
module Chat
  module Group
    class BroadcastService
      # ─── Room lifecycle ────────────────────────────────────────

      def self.room_deleted(room)
        broadcast(room, type: "room_deleted", room_id: room.id)
      end

      def self.member_joined(room, delegate)
        broadcast(room,
          type:     "member_joined",
          delegate: {
            id:         delegate.id,
            name:       delegate.name,
            avatar_url: delegate.avatar_url
          }
        )
      end

      def self.member_left(room, delegate_id)
        broadcast(room, type: "member_left", delegate_id: delegate_id)
      end

      # ─── Messages ──────────────────────────────────────────────

      def self.message_sent(room, msg)
        broadcast(room,
          type:    "group_message",
          room_id: room.id,
          message: GroupChat::MessageSerializer.call(message: msg, sender: msg.sender)
        )
      end

      def self.message_edited(room, msg)
        broadcast(room,
          type:       "group_message_edited",
          room_id:    room.id,
          message_id: msg.id,
          content:    msg.content,
          edited_at:  TimeFormatter.format(msg.edited_at)
        )
      end

      def self.message_deleted(room, msg)
        broadcast(room,
          type:       "group_message_deleted",
          room_id:    room.id,
          message_id: msg.id
        )
      end

      # ─── Read receipts ─────────────────────────────────────────

      def self.bulk_read(room, delegate, message_ids)
        return if message_ids.empty?

        broadcast(room,
          type:        "bulk_read",
          room_id:     room.id,
          message_ids: message_ids,
          reader:      DelegatePresenter.minimal(delegate),
          read_at:     TimeFormatter.format(Time.current)
        )
      end

      # ─── Typing indicators ─────────────────────────────────────

      def self.typing(room, delegate)
        broadcast(room,
          type:        "typing",
          room_id:     room.id,
          delegate_id: delegate.id,
          name:        delegate.name
        )
      end

      def self.stop_typing(room, delegate)
        broadcast(room,
          type:        "stop_typing",
          room_id:     room.id,
          delegate_id: delegate.id
        )
      end

      # ───────────────────────────────────────────────────────────
      private_class_method def self.broadcast(room, payload)
        GroupChatChannel.broadcast_to(room, payload)
      end
    end
  end
end