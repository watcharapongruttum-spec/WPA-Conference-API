class Api::V1::LeaveFormsController < ApplicationController
  def create
    result = LeaveForm.bulk_report!(
      leaves: params[:leaves],
      reporter: current_delegate   # << ตรงนี้
    )

    render json: result
  rescue => e
    render json: { error: e.message }, status: 422
  end
end
