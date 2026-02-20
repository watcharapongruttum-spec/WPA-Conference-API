class Api::V1::LeaveFormsController < ApplicationController
  def create
    result = LeaveForm.bulk_report!(
      leaves: leave_form_params[:leaves],
      reporter: current_delegate
    )

    render json: result

  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def leave_form_params
    params.require(:leave_form).permit(
      leaves: [
        :schedule_id,    # ← เพิ่มบรรทัดนี้
        :start_date,
        :end_date,
        :reason,
        :leave_type_id
      ]
    )
  end
end