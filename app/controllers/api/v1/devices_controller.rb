module Api
  module V1
    class DevicesController < ApplicationController
        def update
            current_delegate.update(device_token: params[:device_token])
            render json: { success: true }
        end
    end
    end
end