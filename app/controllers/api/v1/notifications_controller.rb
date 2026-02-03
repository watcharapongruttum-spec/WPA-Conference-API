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
        # 🔥 FIX: Better error handling and validation
        @notification = current_delegate.notifications.find_by(id: params[:id])
        
        if @notification.nil?
          render json: { 
            error: 'Notification not found or does not belong to you' 
          }, status: :not_found
          return
        end
        
        # 🔥 FIX: Check if already read
        if @notification.read_at.present?
          render json: { 
            message: 'Notification already marked as read',
            data: Api::V1::NotificationSerializer.new(@notification).serializable_hash
          }, status: :ok
          return
        end
        
        if @notification.update(read_at: Time.current)
          render json: @notification, serializer: Api::V1::NotificationSerializer
        else
          render json: { 
            error: 'Failed to mark notification as read',
            errors: @notification.errors.full_messages
          }, status: :unprocessable_entity
        end
      end
      
      # PATCH /api/v1/notifications/mark_all_as_read
      def mark_all_as_read
        # 🔥 FIX: Only update unread notifications
        updated_count = current_delegate.notifications.unread.update_all(read_at: Time.current)
        
        render json: { 
          message: 'All notifications marked as read',
          count: updated_count
        }
      end
    end
  end
end
