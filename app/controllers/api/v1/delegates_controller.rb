# app/controllers/api/v1/delegates_controller.rb
module Api
  module V1
    class DelegatesController < ApplicationController

      
      def index
        @delegates = Delegate.includes(:company, :team)
                             .where.not(name: [nil, ''])
                             .order(name: :asc)
                             .page(params[:page] || 1)
                             .per(20)
        
        render json: @delegates, each_serializer: Api::V1::DelegateSerializer
      end
      
      def show
        @delegate = current_delegate || Delegate.find(params[:id])
        render json: @delegate, serializer: Api::V1::DelegateSerializer
      end
      
      def search
        query = params[:q] || ''
        
        if query.present?
          @delegates = Delegate.includes(:company, :team)
                               .joins("LEFT OUTER JOIN companies ON companies.id = delegates.company_id")
                               .where("LOWER(delegates.name) LIKE ? OR LOWER(companies.name) LIKE ?", 
                                      "%#{query.downcase}%", "%#{query.downcase}%")
                               .where.not(name: [nil, ''])
                               .order(name: :asc)
                               .page(params[:page] || 1)
                               .per(20)
        else
          @delegates = Delegate.includes(:company, :team)
                               .where.not(name: [nil, ''])
                               .order(name: :asc)
                               .page(params[:page] || 1)
                               .per(20)
        end
        
        render json: @delegates, each_serializer: Api::V1::DelegateSerializer
      end
      
      # GET /api/v1/profile
      def profile
        @delegate = current_delegate
        
        if @delegate.nil?
          render json: { error: 'Authentication required' }, status: :unauthorized
          return
        end
        
        render json: @delegate, serializer: Api::V1::DelegateDetailSerializer
      end
      
      # PATCH /api/v1/profile
      def update_profile
        @delegate = current_delegate
        
        if @delegate.nil?
          render json: { error: 'Authentication required' }, status: :unauthorized
          return
        end
        
        if @delegate.update(delegate_params)
          render json: @delegate, serializer: Api::V1::DelegateDetailSerializer
        else
          render json: { 
            error: 'Failed to update profile', 
            errors: @delegate.errors.full_messages 
          }, status: :unprocessable_entity
        end
      end
      










    require 'rqrcode'
    require 'base64'

    def qr_code
      delegate = Delegate.find(params[:id])

      # ข้อมูลที่อยากให้สแกนแล้วได้
      # ปกติจะใส่เป็น URL หรือ delegate_id
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

      base64_png = Base64.encode64(png.to_s)

      render json: {
        qr_code: "data:image/png;base64,#{base64_png}"
      }
    end











      private
      
      def delegate_params
        params.permit(:name, :title, :phone, :avatar)
      end



















    end
  end
end