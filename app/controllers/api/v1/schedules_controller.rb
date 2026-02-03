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
        
        # 🔥 FIX: Validate required parameters
        unless params[:target_id].present?
          render json: { 
            error: 'Target delegate ID is required',
            hint: 'Provide target_id parameter'
          }, status: :unprocessable_entity
          return
        end
        
        unless params[:start_at].present? && params[:end_at].present?
          render json: { 
            error: 'Start and end times are required',
            hint: 'Provide start_at and end_at in ISO 8601 format'
          }, status: :unprocessable_entity
          return
        end
        
        # 🔥 FIX: Get or create conference date
        conference = Conference.find_by(is_current: true) || Conference.first
        
        unless conference
          render json: { 
            error: 'No active conference found' 
          }, status: :not_found
          return
        end
        
        # Parse start_at to get the date
        start_date = DateTime.parse(params[:start_at]).to_date rescue Date.today
        
        # Find or create conference date
        conference_date = ConferenceDate.find_or_create_by!(
          conference: conference,
          on_date: start_date
        )
        
        # 🔥 FIX: Check if target exists
        target = Delegate.find_by(id: params[:target_id])
        
        unless target
          render json: { 
            error: 'Target delegate not found' 
          }, status: :not_found
          return
        end
        
        # 🔥 FIX: Check if booking with self
        if params[:target_id].to_i == @delegate.id
          render json: { 
            error: 'Cannot schedule meeting with yourself' 
          }, status: :unprocessable_entity
          return
        end
        
        @schedule = Schedule.new(
          conference_date: conference_date,
          booker: @delegate,
          target_id: params[:target_id],
          start_at: params[:start_at],
          end_at: params[:end_at],
          table_number: params[:table_number] || "AUTO-#{rand(100..999)}",
          country: params[:country] || @delegate.company&.country
        )
        
        if @schedule.save
          # 🔥 Create notification for target
          notification = Notification.create!(
            delegate: @schedule.target,
            notification_type: 'meeting_scheduled',
            notifiable: @schedule
          )
          
          # 🔥 Broadcast notification
          NotificationChannel.broadcast_to(
            @schedule.target,
            type: 'new_notification',
            notification: {
              id: notification.id,
              type: 'meeting_scheduled',
              created_at: notification.created_at,
              booker: {
                id: @delegate.id,
                name: @delegate.name,
                avatar_url: Api::V1::DelegateSerializer.new(@delegate).avatar_url
              },
              schedule: {
                id: @schedule.id,
                start_at: @schedule.start_at,
                table_number: @schedule.table_number
              }
            }
          )
          
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
        params.permit(:target_id, :start_at, :end_at, :table_number, :country, :conference_date_id)
      end
    end
  end
end
