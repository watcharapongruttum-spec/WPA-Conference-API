# app/controllers/api/v1/admin/connections_controller.rb
module Api
  module V1
    module Admin
      class ConnectionsController < Api::V1::Admin::BaseController
        def index
          page     = (params[:page] || 1).to_i
          per_page = [(params[:per_page] || 20).to_i, 100].min

          scope = Connection
                    .includes(:requester, :target)
                    .order(created_at: :desc)

          scope = scope.where(status: params[:status])           if params[:status].present?
          scope = scope.where(requester_id: params[:delegate_id])
                   .or(scope.where(target_id: params[:delegate_id])) if params[:delegate_id].present?

          total       = scope.count
          connections = scope.offset((page - 1) * per_page).limit(per_page)

          render json: {
            total:       total,
            page:        page,
            per_page:    per_page,
            total_pages: (total.to_f / per_page).ceil,
            connections: connections.map { |c| connection_json(c) }
          }
        end

        def destroy
          connection = Connection.find(params[:id])

          # ลบทั้ง Connection และ ConnectionRequest คู่กัน
          ActiveRecord::Base.transaction do
            ConnectionRequest.where(
              "(requester_id = :a AND target_id = :b) OR (requester_id = :b AND target_id = :a)",
              a: connection.requester_id,
              b: connection.target_id
            ).delete_all

            connection.destroy!
          end

          render json: { success: true, deleted_id: connection.id }
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Connection not found" }, status: :not_found
        rescue StandardError => e
          render json: { error: e.message }, status: :internal_server_error
        end

        private

        def connection_json(c)
          {
            id:         c.id,
            status:     c.status,
            created_at: c.created_at&.iso8601,
            requester: {
              id:         c.requester.id,
              name:       c.requester.name,
              email:      c.requester.email,
              company:    c.requester.company&.name,
              avatar_url: c.requester.avatar_url
            },
            target: {
              id:         c.target.id,
              name:       c.target.name,
              email:      c.target.email,
              company:    c.target.company&.name,
              avatar_url: c.target.avatar_url
            }
          }
        end
      end
    end
  end
end
