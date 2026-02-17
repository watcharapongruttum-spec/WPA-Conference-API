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

        message_unread_count = ChatMessage
                                 .where(
                                   recipient_id: me.id,
                                   read_at: nil,
                                   deleted_at: nil
                                 )
                                 .count

        pending_requests_count = ConnectionRequest
                                   .where(
                                     target_id: me.id,
                                     status: "pending"
                                   )
                                   .count

        {
          unread_notifications_count: system_notifications_count,
          unread_message_notifications_count: message_unread_count,
          new_messages_count: message_unread_count,
          pending_requests_count: pending_requests_count,
          upcoming_schedule_count: booked_upcoming + targeted_upcoming,
          connections_count: connections_count
        }
      end

    end
  end
end
