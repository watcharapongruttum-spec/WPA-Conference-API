# app/controllers/api/v1/admin/audit_logs_controller.rb
module Api
  module V1
    module Admin
      class AuditLogsController < Api::V1::Admin::BaseController
        def index
          page     = (params[:page] || 1).to_i
          per_page = [(params[:per_page] || 50).to_i, 100].min

          scope = AuditLog
                    .includes(:delegate)
                    .order(created_at: :desc)

          scope = scope.where(action: params[:action]) if params[:action].present?
          scope = scope.where(delegate_id: params[:delegate_id]) if params[:delegate_id].present?

          total = scope.count
          logs  = scope.offset((page - 1) * per_page).limit(per_page)

          render json: {
            total:       total,
            page:        page,
            per_page:    per_page,
            total_pages: (total.to_f / per_page).ceil,
            logs:        logs.map { |l|
              {
                id:             l.id,
                action:         l.action,
                auditable_type: l.auditable_type,
                auditable_id:   l.auditable_id,
                ip_address:     l.ip_address,
                created_at:     l.created_at&.iso8601,
                delegate: l.delegate && {
                  id:   l.delegate.id,
                  name: l.delegate.name
                }
              }
            }
          }
        end
      end
    end
  end
end