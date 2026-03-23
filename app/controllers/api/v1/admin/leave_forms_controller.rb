# app/controllers/api/v1/admin/leave_forms_controller.rb
module Api
  module V1
    module Admin
      class LeaveFormsController < Api::V1::Admin::BaseController
        def index
          page     = (params[:page] || 1).to_i
          per_page = [(params[:per_page] || 20).to_i, 100].min

          scope = LeaveForm
                    .includes(:schedule, :leave_type, :reported_by)
                    .order(created_at: :desc)

          scope = scope.where(status: params[:status]) if params[:status].present?

          total = scope.count
          forms = scope.offset((page - 1) * per_page).limit(per_page)

          render json: {
            total:       total,
            page:        page,
            per_page:    per_page,
            total_pages: (total.to_f / per_page).ceil,
            leave_forms: forms.map { |f|
              {
                id:          f.id,
                status:      f.status,
                explanation: f.explanation,
                reported_at: f.reported_at&.iso8601,
                leave_type:  f.leave_type&.name,
                reported_by: f.reported_by && {
                  id:   f.reported_by.id,
                  name: f.reported_by.name
                },
                schedule_id: f.schedule_id
              }
            }
          }
        end
      end
    end
  end
end