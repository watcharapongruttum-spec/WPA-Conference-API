# app/controllers/api/v1/tables_controller.rb
module Api
  module V1
    class TablesController < ApplicationController

      # GET /api/v1/tables/time_view?date=2025-10-13&time=11:00
      def time_view
        render json: Table.time_view(
          params:           params,
          current_delegate: current_delegate
        )
      end

    end
  end
end