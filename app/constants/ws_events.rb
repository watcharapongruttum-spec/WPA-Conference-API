# app/constants/ws_events.rb
#
# Single source of truth สำหรับ WebSocket event names ทั้งหมด
# ใช้ใน Channel, BroadcastService, และ Frontend
#
# Format: namespace:action
#
module WsEvents
  # ─── Direct Chat ──────────────────────────────────
  CHAT_NEW_MESSAGE     = "chat:new_message"
  CHAT_MESSAGE_UPDATED = "chat:message_updated"
  CHAT_MESSAGE_DELETED = "chat:message_deleted"
  CHAT_MESSAGE_READ    = "chat:message_read"
  CHAT_BULK_READ       = "chat:bulk_read"
  CHAT_TYPING_START    = "chat:typing_start"
  CHAT_TYPING_STOP     = "chat:typing_stop"

  # ─── Group Chat ───────────────────────────────────
  GROUP_NEW_MESSAGE     = "group:new_message"
  GROUP_MESSAGE_EDITED  = "group:message_edited"
  GROUP_MESSAGE_DELETED = "group:message_deleted"
  GROUP_BULK_READ       = "group:bulk_read"
  GROUP_TYPING_START    = "group:typing_start"
  GROUP_TYPING_STOP     = "group:typing_stop"

  # ─── Room lifecycle ───────────────────────────────
  ROOM_MEMBER_JOINED = "room:member_joined"
  ROOM_MEMBER_LEFT   = "room:member_left"
  ROOM_DELETED       = "room:deleted"

  # ─── Notifications ────────────────────────────────
  NOTIFICATION_NEW = "notification:new"

  # ─── System ───────────────────────────────────────
  ERROR = "error"
end