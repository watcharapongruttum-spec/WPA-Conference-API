# app/controllers/api/v1/admin/leave_types_controller.rb
module Api
  module V1
    module Admin
      class LeaveTypesController < Api::V1::Admin::BaseController
        def index
          leave_types = LeaveType.order(:name).all
          render json: {
            total:       leave_types.size,
            leave_types: leave_types.map { |lt| leave_type_json(lt) }
          }
        end

        def create
          leave_type = LeaveType.new(leave_type_params)
          leave_type.save!
          render json: leave_type_json(leave_type), status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.join(", ") },
                 status: :unprocessable_entity
        end

        def update
          leave_type = LeaveType.find(params[:id])
          leave_type.update!(leave_type_params)
          render json: leave_type_json(leave_type)
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Leave type not found" }, status: :not_found
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.join(", ") },
                 status: :unprocessable_entity
        end

        def destroy
          leave_type = LeaveType.find(params[:id])

          if leave_type.leave_forms.exists?
            return render json: {
              error: "Cannot delete — this type has #{leave_type.leave_forms.count} leave form(s) using it"
            }, status: :unprocessable_entity
          end

          leave_type.destroy!
          render json: { success: true, deleted_id: leave_type.id }
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Leave type not found" }, status: :not_found
        end

        private

        def leave_type_params
          params.require(:leave_type).permit(:name)
        end

        def leave_type_json(lt)
          {
            id:               lt.id,
            name:             lt.name,
            leave_forms_count: lt.leave_forms.count
          }
        end
      end
    end
  end
end
