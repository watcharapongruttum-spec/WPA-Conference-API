# app/controllers/api/v1/tables_controller.rb
module Api
  module V1
    class TablesController < ApplicationController

      # GET /api/v1/tables/time_view
      def time_view
        result = TableTimeViewService.call(
          params:           params,
          current_delegate: current_delegate
        )
        render json: result
      end

    end
  end
end