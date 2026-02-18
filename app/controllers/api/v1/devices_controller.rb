module Api
  module V1
    class DevicesController < ApplicationController

      # PATCH /api/v1/device_token
      def update
        if device_params[:device_token].blank?
          return render json: { error: "device_token required" }, status: :unprocessable_entity
        end

        current_delegate.update!(device_params)

        render json: { success: true }
      end

      private

      def device_params
        params.require(:device).permit(:device_token)
      end
    end
  end
end
