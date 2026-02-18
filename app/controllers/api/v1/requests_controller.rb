# app/controllers/api/v1/requests_controller.rb
module Api
  module V1
    class RequestsController < ApplicationController

      # ============================
      # GET /api/v1/requests
      # ============================
      def index
        connections = ConnectionRequest
                        .where(requester_id: current_delegate.id)
                        .or(
                          ConnectionRequest.where(target_id: current_delegate.id)
                        )
                        .includes(:requester, :target)
                        .order(created_at: :desc)

        render json: connections,
               each_serializer: Api::V1::ConnectionRequestSerializer
      end


      # ============================
      # POST /api/v1/requests
      # ============================
      def create
        return render json: { error: 'Target ID is required' }, status: :unprocessable_entity unless params[:target_id].present?

        target = Delegate.find_by(id: params[:target_id])
        return render json: { error: 'Target delegate not found' }, status: :not_found unless target

        return render json: { error: 'Cannot send connection request to yourself' },
                      status: :unprocessable_entity if target.id == current_delegate.id

        existing = ConnectionRequest.where(
          requester_id: current_delegate.id,
          target_id: target.id
        ).where(status: [:pending, :accepted]).first

        if existing
          return render json: {
            error: 'Connection request already exists',
            status: existing.status
          }, status: :unprocessable_entity
        end

        ActiveRecord::Base.transaction do
          @connection = ConnectionRequest.create!(
            requester_id: current_delegate.id,
            target_id: target.id,
            status: :pending
          )

          notification = Notification.create!(
            delegate: target,
            notification_type: 'connection_request',
            notifiable: @connection
          )

          AuditLogger.connection_request_created(@connection, request)
          Notification::BroadcastService.call(notification)
        end

        render json: @connection,
               serializer: Api::V1::ConnectionRequestSerializer,
               status: :created
      end


      # ============================
      # PATCH /api/v1/requests/:id/accept
      # ============================
      def accept
        connection = ConnectionRequest.find_by(
          id: params[:id],
          target_id: current_delegate.id,
          status: :pending
        )

        return render_not_found unless connection

        ActiveRecord::Base.transaction do
          connection.update!(status: :accepted)

          notification = Notification.create!(
            delegate: connection.requester,
            notification_type: 'connection_accepted',
            notifiable: connection
          )

          AuditLogger.connection_accepted(connection, request)
          Notification::BroadcastService.call(notification)
        end

        render json: connection,
               serializer: Api::V1::ConnectionRequestSerializer
      end


      # ============================
      # PATCH /api/v1/requests/:id/reject
      # ============================
      def reject
        connection = ConnectionRequest.find_by(
          id: params[:id],
          target_id: current_delegate.id,
          status: :pending
        )

        return render_not_found unless connection

        ActiveRecord::Base.transaction do
          connection.update!(status: :rejected)
          AuditLogger.connection_rejected(connection, request)
        end

        render json: connection,
               serializer: Api::V1::ConnectionRequestSerializer
      end


      # ============================
      # GET /api/v1/requests/my_received
      # ============================
      def my_received
        requests = ConnectionRequest
                    .where(target_id: current_delegate.id, status: :pending)
                    .includes(:requester)

        render json: requests.map { |req|
          {
            id: req.id,
            requester: {
              id: req.requester.id,
              name: req.requester.name,
              title: req.requester.title,
              avatar_url: Api::V1::DelegateSerializer.new(req.requester).avatar_url
            },
            created_at: req.created_at
          }
        }
      end


      private

      def render_not_found
        render json: {
          error: 'Connection request not found or already processed'
        }, status: :not_found
      end

    end
  end
end
