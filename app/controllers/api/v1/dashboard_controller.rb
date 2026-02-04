module Api
  module V1
    class DashboardController < ApplicationController
      before_action :authenticate_delegate!

      def show
        me = current_delegate

        render json: {
          unread_notifications_count: me.notifications.unread.count,
          pending_requests_count: ConnectionRequest.where(target_id: me.id, status: "pending").count,
          new_messages_count: ChatMessage.where(recipient_id: me.id, read_at: nil).count,
          upcoming_schedule_count: me.schedules.where("start_at > ?", Time.current).count,
          connections_count: me.connections.count
        }
      end
    end
  end
end
