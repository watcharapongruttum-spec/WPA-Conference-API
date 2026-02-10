# app/controllers/api/v1/notifications_controller.rb
module Api
  module V1
    class NotificationsController < ApplicationController
      
      # GET /api/v1/notifications
      def index
        @notifications = current_delegate.notifications.order(created_at: :desc)


        case params[:type]
        when 'system'
          @notifications = @notifications.where.not(notification_type: 'new_message')
        when 'message'
          @notifications = @notifications.where(notification_type: 'new_message')
        end

        
        render json: @notifications, each_serializer: Api::V1::NotificationSerializer
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
        scope = current_delegate.notifications.where(read_at: nil)

        case params[:type]
        when 'system'
          scope = scope.where.not(notification_type: 'new_message')
        when 'message'
          scope = scope.where(notification_type: 'new_message')
        end

        updated_count = scope.count
        scope.update_all(read_at: Time.current)

        render json: { 
          message: 'All notifications marked as read',
          count: updated_count
        }
      end


      def unread_count
        scope = current_delegate.notifications.where(read_at: nil)

        case params[:type]
        when 'system'
          scope = scope.where.not(notification_type: 'new_message')
        when 'message'
          scope = scope.where(notification_type: 'new_message')
        end

        render json: { unread_count: scope.count }
      end











    end
  end
end
