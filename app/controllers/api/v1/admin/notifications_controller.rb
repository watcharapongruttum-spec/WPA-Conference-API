# app/controllers/api/v1/admin/notifications_controller.rb
module Api
  module V1
    module Admin
      class NotificationsController < Api::V1::Admin::BaseController
        def index
          page     = (params[:page] || 1).to_i
          per_page = [(params[:per_page] || 50).to_i, 100].min

          scope = Notification
                    .includes(:delegate)
                    .order(created_at: :desc)

          scope = scope.where(delegate_id: params[:delegate_id])         if params[:delegate_id].present?
          scope = scope.where(notification_type: params[:type])          if params[:type].present?
          scope = scope.where(read_at: nil)                              if params[:unread] == "true"

          total         = scope.count
          notifications = scope.offset((page - 1) * per_page).limit(per_page)

          render json: {
            total:       total,
            page:        page,
            per_page:    per_page,
            total_pages: (total.to_f / per_page).ceil,
            notifications: notifications.map { |n|
              {
                id:                n.id,
                notification_type: n.notification_type,
                read_at:           n.read_at&.iso8601,
                created_at:        n.created_at&.iso8601,
                is_read:           n.read_at.present?,
                delegate: n.delegate && {
                  id:    n.delegate.id,
                  name:  n.delegate.name,
                  email: n.delegate.email
                }
              }
            }
          }
        end




        # app/controllers/api/v1/admin/notifications_controller.rb
        def destroy
          notification = Notification.find(params[:id])
          notification.destroy!
          render json: { success: true, deleted_id: notification.id }
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Notification not found" }, status: :not_found
        end

        def destroy_all
          scope = Notification.all
          scope = scope.where(delegate_id: params[:delegate_id]) if params[:delegate_id].present?
          scope = scope.where(notification_type: params[:type])  if params[:type].present?

          count = scope.count
          scope.delete_all

          render json: { success: true, deleted_count: count }
        end






        # ส่ง push notification หา delegate คนใดคนหนึ่งโดยตรง
        def push
          delegate = Delegate.find_by(id: params[:delegate_id])
          return render json: { error: "Delegate not found" }, status: :not_found unless delegate

          unless delegate.device_token.present?
            return render json: { error: "Delegate has no device token" }, status: :unprocessable_entity
          end

          title   = params[:title].to_s.strip
          message = params[:message].to_s.strip

          return render json: { error: "title is required" },   status: :unprocessable_entity if title.blank?
          return render json: { error: "message is required" }, status: :unprocessable_entity if message.blank?

          result = FcmService.send_push(
            token: delegate.device_token,
            title: title,
            body:  message,
            data:  { type: "admin_push", screen: "home" }
          )

          if result
            render json: { success: true, sent_to: { id: delegate.id, name: delegate.name } }
          else
            render json: { error: "Failed to send push" }, status: :unprocessable_entity
          end
        rescue StandardError => e
          render json: { error: e.message }, status: :internal_server_error
        end

        # mark read ทีละ 1
        def mark_read
          notification = Notification.find(params[:id])
          notification.update!(read_at: Time.current) unless notification.read_at.present?
          render json: { success: true, id: notification.id, read_at: notification.read_at&.iso8601 }
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Notification not found" }, status: :not_found
        end

        # mark all read — กรองตาม delegate หรือ type ได้
        def mark_all_read
          scope = Notification.where(read_at: nil)
          scope = scope.where(delegate_id: params[:delegate_id]) if params[:delegate_id].present?
          scope = scope.where(notification_type: params[:type])  if params[:type].present?

          count = scope.count
          scope.update_all(read_at: Time.current)

          render json: { success: true, updated_count: count }
        end





















      end
    end
  end
end