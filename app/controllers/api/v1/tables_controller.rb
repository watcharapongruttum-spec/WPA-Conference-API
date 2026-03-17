# app/controllers/api/v1/tables_controller.rb
module Api
  module V1
    class TablesController < ApplicationController

      # GET /api/v1/tables/time_view
      def time_view
        render json: Table.time_view(
          params:           params,
          current_delegate: current_delegate
        )
      end








      # GET /api/v1/tables/grid_view
      def grid_view
        tables = Table.includes(:teams)
                      .where(conference: Conference.find_by(is_current: true))
                      .order(:table_number)
        render json: tables.map { |t|
          {
            table_number: t.table_number,
            occupancy:    t.teams.count
          }
        }
      end














      

    end
  end
end