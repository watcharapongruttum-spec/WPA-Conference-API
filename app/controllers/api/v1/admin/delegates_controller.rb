# app/controllers/api/v1/admin/delegates_controller.rb
module Api
  module V1
    module Admin
      class DelegatesController < Api::V1::Admin::BaseController
        def index
          page     = (params[:page] || 1).to_i
          per_page = [(params[:per_page] || 20).to_i, 100].min
          keyword  = params[:keyword].to_s.strip.downcase

          scope = Delegate
                    .joins(:company)
                    .includes(:company, :team)
                    .where.not(name: [nil, ""])

          if keyword.present?
            scope = scope.where(
              "LOWER(delegates.name) LIKE :q OR LOWER(companies.name) LIKE :q",
              q: "%#{keyword}%"
            )
          end

          total       = scope.count
          total_pages = (total.to_f / per_page).ceil

          delegates = scope
                        .order(name: :asc)
                        .offset((page - 1) * per_page)
                        .limit(per_page)

          render json: {
            total:       total,
            page:        page,
            per_page:    per_page,
            total_pages: total_pages,
            delegates:   delegates.map { |d| delegate_json(d) }
          }
        end

        def show
          delegate = Delegate.includes(:company, :team).find(params[:id])
          render json: delegate_json(delegate)
        end








        # app/controllers/api/v1/admin/delegates_controller.rb
        def update
          delegate = Delegate.find(params[:id])

          delegate.update!(delegate_update_params)

          render json: delegate_json(delegate.reload)
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Delegate not found" }, status: :not_found
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.join(", ") },
                status: :unprocessable_entity
        end

        private

        def delegate_update_params
          params.permit(:name, :email, :phone)
        end










        def reset_password
          delegate = Delegate.find(params[:id])
          temp_password = delegate.generate_temporary_password(overwrite: true)

          render json: {
            success:        true,
            delegate_id:    delegate.id,
            name:           delegate.name,
            temp_password:  temp_password
          }
        rescue StandardError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def delegate_json(d)
          {
            id:           d.id,
            name:         d.name,
            email:        d.email,
            title:        d.title,
            phone:        d.phone,
            avatar_url:   d.avatar_url,
            has_logged_in: d.has_logged_in,
            first_login_at: d.first_login_at,
            device_token: d.device_token.present?,
            company: d.company && {
              id:      d.company.id,
              name:    d.company.name,
              country: d.company.country
            },
            team: d.team && {
              id:   d.team.id,
              name: d.team.name
            }
          }
        end
      end
    end
  end
end