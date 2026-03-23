module Api
  module V1
    class DelegatesController < ApplicationController
      # ---------------- INDEX ----------------
      def index
        page     = (params[:page] || 1).to_i
        per_page = [(params[:per_page] || 15).to_i, 30].min
        keyword  = params[:keyword].to_s.strip.downcase
        me       = current_delegate

        scope = Delegate
                  .joins(:company)
                  .includes(:company, :team)
                  .where.not(name: [nil, ""])
                  .where.not(id: me.id)
                  .where(<<~SQL)
                    EXISTS (
                      SELECT 1
                      FROM schedules s
                      JOIN conference_dates cd ON cd.id = s.conference_date_id
                      JOIN conferences co ON co.id = cd.conference_id
                      WHERE co.conference_year = '2025'
                        AND (
                          s.booker_id  = delegates.id
                          OR s.delegate_id = delegates.id
                          OR s.target_id   = delegates.team_id
                        )
                    )
                  SQL

        if params[:friends_only].to_s == "true"
          scope = scope.where(id: friend_ids_of(me))
        end

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
          total: total,
          page: page,
          per_page: per_page,
          total_pages: total_pages,
          delegates: ActiveModelSerializers::SerializableResource.new(
            delegates,
            each_serializer: Api::V1::DelegateSerializer,
            scope: me
          )
        }
      end


















      
      # ---------------- SHOW ----------------
      def show
        @delegate = Delegate.find(params[:id])

        if @delegate.id == current_delegate.id
          return render json: { error: "Use /profile for self" }, status: :unprocessable_entity
        end

        render json: @delegate,
               serializer: Api::V1::DelegateSerializer,
               scope: current_delegate
      end

      # ---------------- QR CODE ----------------
      require "rqrcode"
      require "base64"

      def qr_code
        delegate = Delegate.find(params[:id])

        qr_data = { id: delegate.id, name: delegate.name }.to_json
        qr = RQRCode::QRCode.new(qr_data)

        png = qr.as_png(
          bit_depth: 1,
          border_modules: 4,
          color_mode: ChunkyPNG::COLOR_GRAYSCALE,
          size: 300
        )

        render json: {
          qr_code: "data:image/png;base64,#{Base64.strict_encode64(png.to_s)}"
        }
      end





      def me
        render json: {
          valid: true,
          delegate: {
            id:         current_delegate.id,
            name:       current_delegate.name,
            email:      current_delegate.email,
            title:      current_delegate.title,
            company:    current_delegate.company&.name,
            avatar_url: current_delegate.avatar_url
          }
        }
      end






      private

      def friend_ids_of(delegate)
        ConnectionRequest.accepted
                         .where(requester_id: delegate.id)
                         .or(ConnectionRequest.accepted.where(target_id: delegate.id))
                         .pluck(:requester_id, :target_id)
                         .flatten
                         .uniq
                         .reject { |id| id == delegate.id }
      end

      def delegate_params
        params.permit(:name, :title, :phone, :avatar)
      end
    end
  end
end