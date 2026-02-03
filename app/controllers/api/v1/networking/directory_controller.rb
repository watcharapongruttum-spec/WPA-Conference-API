# app/controllers/api/v1/networking/directory_controller.rb
module Api
  module V1
    module Networking
      class DirectoryController < ApplicationController
        def index
          @delegates = Delegate.includes(:company, :team)
                               .page(params[:page] || 1)
                               .per(20)
          
          render json: @delegates, each_serializer: Api::V1::Networking::DirectorySerializer
        end
      end
    end
  end
end