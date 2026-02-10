module Api
  module V1
    class DashboardController < ApplicationController

      def show
        me = current_delegate

        booked_upcoming = me.booked_schedules
          .where("start_at > ?", Time.current)
          .count

        targeted_upcoming = me.targeted_schedules
          .where("start_at > ?", Time.current)
          .count

        connections_count = me.connected_delegates.count

        # 🔔 System notifications (ไม่เกี่ยวกับ chat)
        system_notifications_count = me.notifications
          .where.not(notification_type: 'new_message')
          .where(read_at: nil)
          .count

        # 💬 CHAT BADGE (ใช้ ChatMessage เท่านั้น)
        message_unread_count = ChatMessage
          .where(
            recipient_id: me.id,
            read_at: nil,
            deleted_at: nil
          )
          .count

        render json: {
          unread_notifications_count: system_notifications_count,

          # ตรงนี้ = badge chat
          unread_message_notifications_count: message_unread_count,

          pending_requests_count: ConnectionRequest.where(
            target_id: me.id,
            status: "pending"
          ).count,

          # ใช้อันเดียวกันก็ได้
          new_messages_count: message_unread_count,

          upcoming_schedule_count: booked_upcoming + targeted_upcoming,
          connections_count: connections_count
        }
      end







      
    end
  end
end
