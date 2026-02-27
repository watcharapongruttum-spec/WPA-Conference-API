class AddProductionIndexes < ActiveRecord::Migration[7.0]
  def change
    # ===== CHAT_MESSAGES =====
    # Query: WHERE recipient_id = ? AND read_at IS NULL AND deleted_at IS NULL
    unless index_exists?(:chat_messages,
                         %i[recipient_id read_at deleted_at])
      add_index :chat_messages, %i[recipient_id read_at deleted_at],
                name: 'idx_chat_messages_recipient_unread'
    end

    # Query: WHERE sender_id = ? AND recipient_id = ? ORDER BY created_at
    unless index_exists?(:chat_messages,
                         %i[sender_id recipient_id created_at])
      add_index :chat_messages, %i[sender_id recipient_id created_at],
                name: 'idx_chat_messages_conversation'
    end

    # Query: WHERE chat_room_id = ? ORDER BY created_at
    unless index_exists?(:chat_messages, %i[chat_room_id created_at])
      add_index :chat_messages, %i[chat_room_id created_at],
                name: 'idx_chat_messages_room_timeline'
    end

    # Query: WHERE delivered_at IS NULL AND deleted_at IS NULL
    unless index_exists?(:chat_messages, %i[delivered_at deleted_at])
      add_index :chat_messages, %i[delivered_at deleted_at],
                name: 'idx_chat_messages_undelivered'
    end

    # ===== NOTIFICATIONS =====
    # Query: WHERE delegate_id = ? AND read_at IS NULL
    unless index_exists?(:notifications, %i[delegate_id read_at])
      add_index :notifications, %i[delegate_id read_at],
                name: 'idx_notifications_unread'
    end

    # Query: WHERE delegate_id = ? AND notification_type != 'new_message'
    unless index_exists?(:notifications,
                         %i[delegate_id notification_type read_at])
      add_index :notifications, %i[delegate_id notification_type read_at],
                name: 'idx_notifications_by_type'
    end

    # ===== CONNECTION_REQUESTS =====
    # Query: WHERE target_id = ? AND status = 'pending'
    unless index_exists?(:connection_requests, %i[target_id status])
      add_index :connection_requests, %i[target_id status],
                name: 'idx_connection_requests_pending'
    end

    # ===== SCHEDULES =====
    # Query: WHERE delegate_id = ? AND start_at > ?
    unless index_exists?(:schedules, %i[delegate_id start_at])
      add_index :schedules, %i[delegate_id start_at],
                name: 'idx_schedules_upcoming'
    end

    unless index_exists?(:schedules, %i[booker_id start_at])
      add_index :schedules, %i[booker_id start_at],
                name: 'idx_schedules_booker_upcoming'
    end

    # ===== DELEGATES =====
    # Query: WHERE email = ? (login) - unique constraint
    unless index_exists?(:delegates, :email)
      add_index :delegates, :email, unique: true,
                                    name: 'idx_delegates_email_unique'
    end

    # Query: WHERE device_token = ? (push notification)
    unless index_exists?(:delegates, :device_token)
      add_index :delegates, :device_token,
                name: 'idx_delegates_device_token'
    end

    # ===== CHAT_ROOMS =====
    return if index_exists?(:chat_rooms, %i[deleted_at room_kind])

    add_index :chat_rooms, %i[deleted_at room_kind],
              name: 'idx_chat_rooms_active_kind'
  end
end
