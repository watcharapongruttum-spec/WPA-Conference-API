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
      end
    end
  end
end