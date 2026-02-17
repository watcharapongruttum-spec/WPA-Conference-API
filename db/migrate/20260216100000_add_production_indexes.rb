class AddProductionIndexes < ActiveRecord::Migration[7.0]
  def change
    # ===== CHAT_MESSAGES =====
    # Query: WHERE recipient_id = ? AND read_at IS NULL AND deleted_at IS NULL
    add_index :chat_messages, [:recipient_id, :read_at, :deleted_at], 
              name: 'idx_chat_messages_recipient_unread' unless index_exists?(:chat_messages, [:recipient_id, :read_at, :deleted_at])
    
    # Query: WHERE sender_id = ? AND recipient_id = ? ORDER BY created_at
    add_index :chat_messages, [:sender_id, :recipient_id, :created_at], 
              name: 'idx_chat_messages_conversation' unless index_exists?(:chat_messages, [:sender_id, :recipient_id, :created_at])
    
    # Query: WHERE chat_room_id = ? ORDER BY created_at
    add_index :chat_messages, [:chat_room_id, :created_at], 
              name: 'idx_chat_messages_room_timeline' unless index_exists?(:chat_messages, [:chat_room_id, :created_at])
    
    # Query: WHERE delivered_at IS NULL AND deleted_at IS NULL
    add_index :chat_messages, [:delivered_at, :deleted_at], 
              name: 'idx_chat_messages_undelivered' unless index_exists?(:chat_messages, [:delivered_at, :deleted_at])
    
    # ===== NOTIFICATIONS =====
    # Query: WHERE delegate_id = ? AND read_at IS NULL
    add_index :notifications, [:delegate_id, :read_at], 
              name: 'idx_notifications_unread' unless index_exists?(:notifications, [:delegate_id, :read_at])
    
    # Query: WHERE delegate_id = ? AND notification_type != 'new_message'
    add_index :notifications, [:delegate_id, :notification_type, :read_at], 
              name: 'idx_notifications_by_type' unless index_exists?(:notifications, [:delegate_id, :notification_type, :read_at])
    
    # ===== CONNECTION_REQUESTS =====
    # Query: WHERE target_id = ? AND status = 'pending'
    add_index :connection_requests, [:target_id, :status], 
              name: 'idx_connection_requests_pending' unless index_exists?(:connection_requests, [:target_id, :status])
    
    # ===== SCHEDULES =====
    # Query: WHERE delegate_id = ? AND start_at > ?
    add_index :schedules, [:delegate_id, :start_at], 
              name: 'idx_schedules_upcoming' unless index_exists?(:schedules, [:delegate_id, :start_at])
    
    add_index :schedules, [:booker_id, :start_at], 
              name: 'idx_schedules_booker_upcoming' unless index_exists?(:schedules, [:booker_id, :start_at])
    
    # ===== DELEGATES =====
    # Query: WHERE email = ? (login) - unique constraint
    add_index :delegates, :email, unique: true, 
              name: 'idx_delegates_email_unique' unless index_exists?(:delegates, :email)
    
    # Query: WHERE device_token = ? (push notification)
    add_index :delegates, :device_token, 
              name: 'idx_delegates_device_token' unless index_exists?(:delegates, :device_token)
    
    # ===== CHAT_ROOMS =====
    add_index :chat_rooms, [:deleted_at, :room_kind], 
              name: 'idx_chat_rooms_active_kind' unless index_exists?(:chat_rooms, [:deleted_at, :room_kind])
  end
end