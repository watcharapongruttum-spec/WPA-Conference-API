module Api
  module V1
    class DashboardController < ApplicationController

      def show
        me = current_delegate

        cache_key = "dashboard:#{me.id}:v1"

        data = Rails.cache.fetch(cache_key, expires_in: 30.seconds) do
          build_dashboard_data(me)
        end

        render json: data
      end

      private

      def build_dashboard_data(me)
        now = Time.current

        booked_upcoming = me.booked_schedules
                            .where("start_at > ?", now)
                            .count

        targeted_upcoming = me.targeted_schedules
                              .where("start_at > ?", now)
                              .count

        connections_count = me.connected_delegates.count

        system_notifications_count = me.notifications
                                      .where.not(notification_type: 'new_message')
                                      .where(read_at: nil)
                                      .count

        # ✅ แชท 1-1 unread (ใช้ read_at บน chat_messages — ถูกต้องสำหรับ direct chat)
        direct_unread = ChatMessage
                          .where(
                            recipient_id: me.id,
                            read_at:      nil,
                            deleted_at:   nil
                          )
                          .count

        # ✅ FIX: Group chat unread — ดูจาก message_reads table
        # ไม่ใช้ read_at บน chat_messages เพราะ group chat mark read ผ่าน MessageRead
        group_room_ids = ChatRoomMember
                          .joins(:chat_room)
                          .where(delegate_id: me.id)
                          .where(chat_rooms: { deleted_at: nil })
                          .pluck(:chat_room_id)

        group_unread = if group_room_ids.any?
          # หา messages ใน group rooms ที่ me ยังไม่ได้อ่าน
          # = messages ที่ไม่มีใน message_reads ของ me
          ChatMessage
            .where(chat_room_id: group_room_ids)
            .where(deleted_at: nil)
            .where.not(sender_id: me.id)
            .where.not(
              id: MessageRead.where(delegate_id: me.id).select(:chat_message_id)
            )
            .count
        else
          0
        end

        message_unread_count = direct_unread + group_unread

        pending_requests_count = ConnectionRequest
                                  .where(
                                    target_id: me.id,
                                    status:    "pending"
                                  )
                                  .count

        {
          unread_notifications_count:         system_notifications_count,
          unread_message_notifications_count: message_unread_count,
          new_messages_count:                 message_unread_count,
          pending_requests_count:             pending_requests_count,
          upcoming_schedule_count:            booked_upcoming + targeted_upcoming,
          connections_count:                  connections_count
        }
      end

    end
  end
end