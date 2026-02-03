# app/controllers/api/v1/schedules_controller.rb
module Api
  module V1
    class SchedulesController < ApplicationController

      
      def index
        if current_delegate
          @schedules = Schedule.where(booker: current_delegate)
                               .or(Schedule.where(target: current_delegate))
                               .includes(:conference_date, :booker, :target)
                               .order(start_at: :asc)
        else
          @schedules = Schedule.includes(:conference_date, :booker, :target)
                               .order(start_at: :asc)
                               .limit(50)
        end
        
        render json: @schedules, each_serializer: Api::V1::ScheduleSerializer
      end
      
      def my_schedule
        @delegate = current_delegate
        
        if @delegate.nil?
          render json: { error: 'Authentication required' }, status: :unauthorized
          return
        end
        
        @schedules = Schedule.where(booker: @delegate)
                             .or(Schedule.where(target: @delegate))
                             .includes(:conference_date, :booker, :target)
                             .order(start_at: :asc)
        
        render json: {
          today: @schedules.select { |s| s.start_at.to_date == Date.today },
          upcoming: @schedules.select { |s| s.start_at.to_date > Date.today }
        }
      end
      
      # สร้างการนัดหมายใหม่
      def create
        @delegate = current_delegate
        
        if @delegate.nil?
          render json: { error: 'Authentication required' }, status: :unauthorized
          return
        end
        
        @schedule = Schedule.new(schedule_params)
        @schedule.booker = @delegate
        
        if @schedule.save
          render json: @schedule, serializer: Api::V1::ScheduleDetailSerializer, status: :created
        else
          render json: { 
            error: 'Failed to create schedule', 
            errors: @schedule.errors.full_messages 
          }, status: :unprocessable_entity
        end
      end
      
      private
      
      def schedule_params
        params.permit(:target_id, :start_at, :end_at, :table_number, :country)
      end
    end
  end
end