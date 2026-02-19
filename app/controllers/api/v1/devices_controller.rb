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

        return render json: { success: true } if current_delegate.device_token == token

        current_delegate.update!(device_token: token)
        render json: { success: true }
      end

      private

      def device_params
        params.require(:device).permit(:device_token)
      end



    end
  end
end
