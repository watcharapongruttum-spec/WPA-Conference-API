class Api::V1::LeaveFormsController < ApplicationController

  def create
    result = LeaveForm.bulk_report!(
      leaves: leave_form_params[:leaves],
      reporter: current_delegate
    )

    if result[:success]
      render json: result
    else
      render json: result, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end







  private

  def leave_form_params
    params.require(:leave_form).permit(
      leaves: [
        :schedule_id,
        :start_date,
        :end_date,
        :reason,
        :leave_type_id,
        :explanation  # ✅ FIX #5: เพิ่ม :explanation ที่ขาดหายไป
                      # เดิม bulk_report! ได้รับ explanation = nil เสมอ
      ]
    )
  end
end
