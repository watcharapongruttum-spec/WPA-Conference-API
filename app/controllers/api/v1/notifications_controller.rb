# app/controllers/api/v1/notifications_controller.rb
module Api
  module V1
    class NotificationsController < ApplicationController
      
      # GET /api/v1/notifications
      def index
        @notifications = current_delegate.notifications
                                       .includes(:notifiable)
                                       .order(created_at: :desc)
                                       .page(params[:page] || 1)
                                       .per(50)
        
        render json: @notifications, each_serializer: Api::V1::NotificationSerializer
      end
      
      # GET /api/v1/notifications/unread_count
      def unread_count
        count = current_delegate.notifications.unread.count
        
        render json: { unread_count: count }
      end
      
      # PATCH /api/v1/notifications/:id/mark_as_read
      def mark_as_read
        @notification = current_delegate.notifications.find(params[:id])
        
        if @notification.mark_as_read!
          render json: @notification, serializer: Api::V1::NotificationSerializer
        else
          render json: { error: 'Failed to mark notification as read' }, status: :unprocessable_entity
        end
      end
      
      # PATCH /api/v1/notifications/mark_all_as_read
      def mark_all_as_read
        current_delegate.notifications.unread.update_all(read_at: Time.current)
        
        render json: { message: 'All notifications marked as read' }
      end
    end
  end
end