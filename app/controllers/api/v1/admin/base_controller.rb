# app/controllers/api/v1/admin/base_controller.rb
module Api
  module V1
    module Admin
      class BaseController < ActionController::API
        include AdminAuthenticatable
        skip_before_action :authenticate_delegate!, raise: false
      end
    end
  end
end