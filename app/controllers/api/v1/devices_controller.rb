module Api
  module V1
    class DevicesController < ApplicationController

      # PATCH /api/v1/device_token
      def update
        token = device_params[:device_token]

        return render json: { error: "device_token required" }, status: :unprocessable_entity if token.blank?
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
