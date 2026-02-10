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

        # 🔔 System notifications
        system_notifications_count = me.notifications
          .where.not(notification_type: 'new_message')
          .where(read_at: nil)
          .count

        # 💬 Message notifications
        message_notifications_count = me.notifications
          .where(notification_type: 'new_message')
          .where(read_at: nil)
          .count

        render json: {
          unread_notifications_count: system_notifications_count,
          unread_message_notifications_count: message_notifications_count,
          pending_requests_count: ConnectionRequest.where(
            target_id: me.id,
            status: "pending"
          ).count,
          new_messages_count: ChatMessage.where(
            recipient_id: me.id,
            read_at: nil
          ).count,
          upcoming_schedule_count: booked_upcoming + targeted_upcoming,
          connections_count: connections_count
        }
      end
    end
  end
end
