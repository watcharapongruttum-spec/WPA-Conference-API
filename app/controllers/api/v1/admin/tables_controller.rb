# app/controllers/api/v1/admin/tables_controller.rb
module Api
  module V1
    module Admin
      class TablesController < Api::V1::Admin::BaseController
        def time_view
          params[:date] ||= "2025-10-13"
          params[:time] ||= "11:00"

          render json: Table.time_view(
            params:           params,
            current_delegate: nil
          )
        end
      end
    end
  end
end