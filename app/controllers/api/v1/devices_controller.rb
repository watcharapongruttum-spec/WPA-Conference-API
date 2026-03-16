# app/controllers/api/v1/devices_controller.rb
module Api
  module V1
    class DevicesController < ApplicationController
      # PATCH /api/v1/device_token
      def update
        unless params[:device].present?
          return render json: { error: "Missing parameter: device" },
                        status: :unprocessable_entity
        end

        token = params[:device][:device_token]

        if token.blank?
          return render json: { error: "Missing parameter: device_token" },
                        status: :unprocessable_entity
        end

        # ✅ ไม่ต้องทำอะไรถ้า token เหมือนเดิม
        return render json: { success: true } if current_delegate.device_token == token

        ActiveRecord::Base.transaction do
          # ✅ kick token เก่าออก + invalidate JWT ของ delegate อื่นที่เคยใช้ device นี้
          Delegate.where(device_token: token)
                  .where.not(id: current_delegate.id)
                  .each do |old_delegate|
                    old_delegate.invalidate_all_tokens!
                    old_delegate.update!(device_token: nil)
                  end

          current_delegate.update!(device_token: token)
        end

        render json: { success: true }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end






      
      private

      def device_params
        params.require(:device).permit(:device_token)
      end
    end
  end
end
