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
      




      # def my_schedule
      #   @delegate = current_delegate
        
      #   if @delegate.nil?
      #     render json: { error: 'Authentication required' }, status: :unauthorized
      #     return
      #   end
        
      #   @schedules = Schedule.where(booker: @delegate)
      #                        .or(Schedule.where(target: @delegate))
      #                        .includes(:conference_date, :booker, :target)
      #                        .order(start_at: :asc)
        
      #   render json: {
      #     today: @schedules.select { |s| s.start_at.to_date == Date.today },
      #     upcoming: @schedules.select { |s| s.start_at.to_date > Date.today }
      #   }
      # end

def my_schedule
  delegate = current_delegate
  return render json: { error: 'Authentication required' }, status: :unauthorized if delegate.nil?

  # -------- 1. YEARS THAT THIS DELEGATE HAS --------
  delegate_years = Schedule
    .joins(conference_date: :conference)
    .where("schedules.booker_id = :id OR schedules.target_id = :id", id: delegate.id)
    .pluck("conferences.conference_year")
    .uniq
    .sort

  # -------- 2. YEAR --------
  year = params[:year].presence || delegate_years.last || Date.today.year.to_s
  conference = Conference.find_by(conference_year: year)

  return render json: {
    error: 'Conference not found',
    available_years: delegate_years
  }, status: :not_found unless conference

  # -------- 3. AVAILABLE DATES IN THIS YEAR --------
    available_dates = conference.conference_dates
      .where("EXTRACT(YEAR FROM on_date) = ?", year.to_i)
      .order(:on_date)
      .pluck(:on_date)


  # -------- 4. SELECTED DATE --------
  if params[:date].present?
    selected_date = Date.parse(params[:date]) rescue nil
  else
    selected_date = available_dates.first
  end

  return render json: {
    error: 'No conference dates',
    available_years: delegate_years
  }, status: :not_found if selected_date.nil?




  # -------- 2. DATE --------
  if params[:date].present?
    selected_date = Date.parse(params[:date]) rescue nil
  else
    cd_with_schedule = Schedule
      .joins(:conference_date)
      .where(conference_dates: { conference_id: conference.id })
      .where("schedules.booker_id = :id OR schedules.target_id = :id", id: delegate.id)
      .order("conference_dates.on_date ASC")
      .first

    selected_date =
      cd_with_schedule&.conference_date&.on_date ||
      conference.conference_dates.order(:on_date).first&.on_date
  end

  return render json: { error: 'No conference dates' }, status: :not_found if selected_date.nil?

  # <<<<<< ตรงนี้สำคัญ
  conference_date = conference.conference_dates.find_by(on_date: selected_date)















  # -------- 5. QUERY SCHEDULE --------
  schedules = Schedule
                .where(conference_date: conference_date)
                .where(booker: delegate)
                .or(
                  Schedule.where(conference_date: conference_date, target: delegate)
                )
                .includes(:booker, :target, :conference_date)
                .order(:start_at)

  # -------- 6. RESPONSE --------
  render json: {
    available_years: delegate_years,
    year: year,
    available_dates: available_dates,
    date: selected_date,
    schedules: schedules
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
