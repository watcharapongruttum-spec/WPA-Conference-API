# app/controllers/api/v1/admin/security_logs_controller.rb
module Api
  module V1
    module Admin
      class SecurityLogsController < Api::V1::Admin::BaseController
        def index
          page     = (params[:page] || 1).to_i
          per_page = [(params[:per_page] || 50).to_i, 100].min

          scope = SecurityLog
                    .includes(:delegate)
                    .order(created_at: :desc)

          scope = scope.where(delegate_id: params[:delegate_id]) if params[:delegate_id].present?
          scope = scope.where(event: params[:event])             if params[:event].present?

          total = scope.count
          logs  = scope.offset((page - 1) * per_page).limit(per_page)

          render json: {
            total:       total,
            page:        page,
            per_page:    per_page,
            total_pages: (total.to_f / per_page).ceil,
            logs:        logs.map { |l|
              {
                id:         l.id,
                event:      l.event,
                ip:         l.ip,
                created_at: l.created_at&.iso8601,
                delegate:   l.delegate && {
                  id:    l.delegate.id,
                  name:  l.delegate.name,
                  email: l.delegate.email
                }
              }
            }
          }
        end
      end
    end
  end
end