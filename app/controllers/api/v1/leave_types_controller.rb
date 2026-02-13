module Api
  module V1
    

    class LeaveTypesController < ApplicationController
  before_action :set_leave_type, only: [:show, :update, :destroy]

  def index
    render json: LeaveType.all
  end

  def show
    render json: @leave_type
  end

  def create
    leave_type = LeaveType.new(leave_type_params)
    if leave_type.save
      render json: leave_type, status: :created
    else
      render json: leave_type.errors, status: :unprocessable_entity
    end
  end

  def update
    if @leave_type.update(leave_type_params)
      render json: @leave_type
    else
      render json: @leave_type.errors, status: :unprocessable_entity
    end
  end

  def destroy
    @leave_type.destroy
    head :no_content
  end

  private

  def set_leave_type
    @leave_type = LeaveType.find(params[:id])
  end

  def leave_type_params
    params.require(:leave_type).permit(:name)
  end
end

end
end