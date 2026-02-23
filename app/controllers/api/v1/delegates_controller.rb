module Api
  module V1
    class DelegatesController < ApplicationController

      # ---------------- INDEX ----------------
      # GET /api/v1/delegates
      # GET /api/v1/delegates?keyword=john
      # GET /api/v1/delegates?friends_only=true
      # GET /api/v1/delegates?keyword=john&friends_only=true&page=1&per_page=20
      def index
        page     = (params[:page] || 1).to_i
        per_page = [(params[:per_page] || 40).to_i, 100].min
        keyword  = params[:keyword].to_s.strip.downcase
        me       = current_delegate

        scope = Delegate
                  .includes(:company, :team)
                  .left_joins(:company)
                  .where.not(name: [nil, ''])
                  .where.not(id: me.id)

        # filter เฉพาะเพื่อน
        if params[:friends_only].to_s == 'true'
          scope = scope.where(id: friend_ids_of(me))
        end

        # ค้นหาด้วย keyword
        if keyword.present?
          scope = scope.where(
            "LOWER(delegates.name) LIKE :q OR LOWER(companies.name) LIKE :q",
            q: "%#{keyword}%"
          )
        end

        total = scope.count

        delegates = scope
                      .order(name: :asc)
                      .page(page)
                      .per(per_page)

        render json: {
          meta: {
            total: total,
            page: page,
            per_page: per_page,
            total_pages: (total.to_f / per_page).ceil
          },
          data: ActiveModelSerializers::SerializableResource.new(
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

      # ---------------- PROFILE ----------------
      def profile
        @delegate = current_delegate

        if @delegate.nil?
          render json: { error: 'Authentication required' }, status: :unauthorized
          return
        end

        render json: @delegate,
               serializer: Api::V1::DelegateDetailSerializer
      end

      # ---------------- UPDATE PROFILE ----------------
      def update_profile
        @delegate = current_delegate

        if @delegate.nil?
          render json: { error: 'Authentication required' }, status: :unauthorized
          return
        end

        if @delegate.update(delegate_params)
          render json: @delegate,
                 serializer: Api::V1::DelegateDetailSerializer
        else
          render json: {
            error: 'Failed to update profile',
            errors: @delegate.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # ---------------- QR CODE ----------------
      require 'rqrcode'
      require 'base64'

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