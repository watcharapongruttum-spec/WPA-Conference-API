# app/controllers/api/v1/admin/connection_requests_controller.rb
module Api
  module V1
    module Admin
      class ConnectionRequestsController < Api::V1::Admin::BaseController
        def index
          page     = (params[:page] || 1).to_i
          per_page = [(params[:per_page] || 20).to_i, 100].min

          scope = ConnectionRequest
                    .includes(:requester, :target)
                    .order(created_at: :desc)

          scope = scope.where(status: params[:status]) if params[:status].present?

          total    = scope.count
          requests = scope.offset((page - 1) * per_page).limit(per_page)

          render json: {
            total:       total,
            page:        page,
            per_page:    per_page,
            total_pages: (total.to_f / per_page).ceil,
            requests:    requests.map { |r|
              {
                id:         r.id,
                status:     r.status,
                created_at: r.created_at&.iso8601,
                requester: {
                  id:    r.requester.id,
                  name:  r.requester.name,
                  email: r.requester.email
                },
                target: {
                  id:    r.target.id,
                  name:  r.target.name,
                  email: r.target.email
                }
              }
            }
          }
        end
      end
    end
  end
end
