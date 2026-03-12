# app/services/chat/broadcast_service.rb
#
# Central point สำหรับ broadcast WebSocket events ทั้งหมด
# ทั้ง Channel และ Controller ใช้ที่นี่ที่เดียว — ห้าม broadcast ตรงจากที่อื่น
#
require_dependency "ws_events"

module Chat
  class BroadcastService

    # =========================================================
    # DIRECT CHAT
    # =========================================================

    def self.new_message(message)
      _broadcast_to_pair(message, {
        type:    WsEvents::CHAT_NEW_MESSAGE,
        message: _serialize_direct(message)
      })
    end

    def self.message_updated(message)
      _broadcast_to_pair(message, {
        type:       WsEvents::CHAT_MESSAGE_UPDATED,
        message_id: message.id,
        content:    message.content,
        edited_at:  _fmt(message.edited_at)
      })
    end

    def self.message_deleted(message)
      _broadcast_to_pair(message, {
        type:       WsEvents::CHAT_MESSAGE_DELETED,
        message_id: message.id
      })
    end

    def self.message_read(message, read_at:)
      _broadcast_to_pair(message, {
        type:       WsEvents::CHAT_MESSAGE_READ,
        message_id: message.id,
        read_at:    _fmt(read_at)
      })
    end

    # bulk_read สำหรับ direct chat
    # reader = Delegate ที่เพิ่งอ่าน, message_ids = [id, ...]
    def self.bulk_read_direct(message_ids:, reader:, read_at:)
      return if message_ids.blank?

      payload = {
        type:        WsEvents::CHAT_BULK_READ,
        message_ids: message_ids,
        read_at:     _fmt(read_at)
      }

      sender_ids = ChatMessage.where(id: message_ids).distinct.pluck(:sender_id)
      Delegate.where(id: sender_ids).find_each { |d| ChatChannel.broadcast_to(d, payload) }
      ChatChannel.broadcast_to(reader, payload) if reader
    end

    def self.typing_start(recipient, sender_id:)
      ChatChannel.broadcast_to(recipient, {
        type:      WsEvents::CHAT_TYPING_START,
        sender_id: sender_id
      })
    end

    def self.typing_stop(recipient, sender_id:)
      ChatChannel.broadcast_to(recipient, {
        type:      WsEvents::CHAT_TYPING_STOP,
        sender_id: sender_id
      })
    end

    # =========================================================
    # GROUP CHAT
    # =========================================================

    def self.group_new_message(room, message)
      GroupChatChannel.broadcast_to(room, {
        type:    WsEvents::GROUP_NEW_MESSAGE,
        room_id: room.id,
        message: GroupChat::MessageSerializer.call(message: message, sender: message.sender)
      })
    end

    def self.group_message_edited(room, message)
      GroupChatChannel.broadcast_to(room, {
        type:       WsEvents::GROUP_MESSAGE_EDITED,
        room_id:    room.id,
        message_id: message.id,
        content:    message.content,
        edited_at:  _fmt(message.edited_at)
      })
    end

    def self.group_message_deleted(room, message)
      GroupChatChannel.broadcast_to(room, {
        type:       WsEvents::GROUP_MESSAGE_DELETED,
        room_id:    room.id,
        message_id: message.id
      })
    end

    def self.group_bulk_read(room, message_ids:, reader:, read_at:)
      return if message_ids.blank?

      GroupChatChannel.broadcast_to(room, {
        type:        WsEvents::GROUP_BULK_READ,
        room_id:     room.id,
        message_ids: message_ids,
        reader:      DelegatePresenter.minimal(reader),
        read_at:     _fmt(read_at)
      })
    end

    def self.group_typing_start(room, delegate)
      GroupChatChannel.broadcast_to(room, {
        type:        WsEvents::GROUP_TYPING_START,
        room_id:     room.id,
        delegate_id: delegate.id,
        name:        delegate.name
      })
    end

    def self.group_typing_stop(room, delegate)
      GroupChatChannel.broadcast_to(room, {
        type:        WsEvents::GROUP_TYPING_STOP,
        room_id:     room.id,
        delegate_id: delegate.id
      })
    end

    # =========================================================
    # ROOM LIFECYCLE
    # =========================================================

    def self.room_member_joined(room, delegate)
      GroupChatChannel.broadcast_to(room, {
        type:     WsEvents::ROOM_MEMBER_JOINED,
        room_id:  room.id,
        delegate: DelegatePresenter.minimal(delegate)
      })
    end

    def self.room_member_left(room, delegate_id)
      GroupChatChannel.broadcast_to(room, {
        type:        WsEvents::ROOM_MEMBER_LEFT,
        room_id:     room.id,
        delegate_id: delegate_id
      })
    end

    def self.room_deleted(room)
      GroupChatChannel.broadcast_to(room, {
        type:    WsEvents::ROOM_DELETED,
        room_id: room.id
      })
    end

    # =========================================================
    # PRIVATE
    # =========================================================

    def self._broadcast_to_pair(message, payload)
      ChatChannel.broadcast_to(message.sender,    payload)
      ChatChannel.broadcast_to(message.recipient, payload)
    end
    private_class_method :_broadcast_to_pair

    def self._serialize_direct(message)
      ChatMessage
        .includes(sender: :company, recipient: :company)
        .find(message.id)
        .then { |m| Api::V1::ChatMessageSerializer.new(m).serializable_hash }
    end
    private_class_method :_serialize_direct

    def self._fmt(time)
      TimeFormatter.format(time)
    end
    private_class_method :_fmt
  end
end