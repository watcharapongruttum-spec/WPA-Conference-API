module Api
  module V1
    class DelegatesController < ApplicationController

      # ---------------- INDEX ----------------
      def index
        @delegates = Delegate.includes(:company, :team)
                             .where.not(name: [nil, ''])
                             .order(name: :asc)
                             .page(params[:page] || 1)
                             .per(20)

        render json: @delegates,
               each_serializer: Api::V1::DelegateSerializer,
               scope: current_delegate
      end

      # ---------------- SHOW ----------------
      def show
        @delegate = Delegate.find(params[:id])

        # ไม่ให้ดูตัวเองผ่าน /delegates/:id
        if @delegate.id == current_delegate.id
          return render json: { error: "Use /profile for self" }, status: :unprocessable_entity
        end

        render json: @delegate,
              serializer: Api::V1::DelegateSerializer,
              scope: current_delegate
      end


      # ---------------- SEARCH ----------------
      def search
        keyword = params[:keyword].to_s.strip.downcase
        me = current_delegate

        # ----- pagination -----
        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 50).to_i
        per_page = 100 if per_page > 100   # กันยิงหนัก

        scope = Delegate
                  .includes(:company, :team)
                  .left_joins(:company)
                  .where.not(name: [nil, ''])

        # ไม่ให้เจอตัวเอง
        scope = scope.where.not(id: me.id) if me.present?

        if keyword.present?
          scope = scope.where(
            "LOWER(delegates.name) LIKE :q
            OR LOWER(companies.name) LIKE :q",
            q: "%#{keyword}%"
          )
        end

        total_count = scope.count

        delegates = scope
                      .order(name: :asc)
                      .page(page)
                      .per(per_page)

        render json: {
          data: ActiveModelSerializers::SerializableResource.new(
            delegates,
            each_serializer: Api::V1::DelegateSerializer,
            scope: current_delegate
          ),
          meta: {
            page: page,
            per_page: per_page,
            total: total_count,
            total_pages: (total_count.to_f / per_page).ceil
          }
        }
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

        qr_data = {
          id: delegate.id,
          name: delegate.name
        }.to_json

        qr = RQRCode::QRCode.new(qr_data)

        png = qr.as_png(
          bit_depth: 1,
          border_modules: 4,
          color_mode: ChunkyPNG::COLOR_GRAYSCALE,
          size: 300
        )

        base64_png = Base64.strict_encode64(png.to_s)

        render json: {
          qr_code: "data:image/png;base64,#{base64_png}"
        }
      end

      private

      # ---------------- PARAMS ----------------
      def delegate_params
        params.permit(:name, :title, :phone, :avatar)
      end

    end
  end
end
