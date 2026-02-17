# app/controllers/api/v1/requests_controller.rb
module Api
  module V1
    class RequestsController < ApplicationController

      
      # GET /api/v1/requests
      def index
        @connections = current_delegate.connection_requests_as_requester
                                       .or(current_delegate.connection_requests_as_target)
                                       .includes(:requester, :target)
                                       .order(created_at: :desc)
        
        render json: @connections, each_serializer: Api::V1::ConnectionRequestSerializer
      end
      

      # POST /api/v1/requests
      def create
        unless params[:target_id].present?
          return render json: {
            error: 'Target ID is required'
          }, status: :unprocessable_entity
        end

        target = Delegate.find_by(id: params[:target_id])
        return render json: { error: 'Target delegate not found' }, status: :not_found unless target

        if target.id == current_delegate.id
          return render json: { error: 'Cannot send connection request to yourself' }, status: :unprocessable_entity
        end

        existing = ConnectionRequest.find_by(
          requester_id: current_delegate.id,
          target_id: target.id
        )

        if existing
          return render json: {
            error: 'Connection request already exists',
            status: existing.status
          }, status: :unprocessable_entity
        end

        ActiveRecord::Base.transaction do
          @connection = ConnectionRequest.create!(
            requester: current_delegate,
            target: target
          )

          notification = Notification.create!(
            delegate: target,
            notification_type: 'connection_request',
            notifiable: @connection
          )

          # 🔥 AUDIT
          AuditLogger.connection_request_created(@connection, request)

          NotificationChannel.broadcast_to(
            target,
            type: 'new_notification',
            notification: {
              id: notification.id,
              type: 'connection_request',
              created_at: notification.created_at,
              requester: {
                id: current_delegate.id,
                name: current_delegate.name,
                avatar_url: current_delegate.avatar_url
              }
            }
          )
        end

        render json: @connection,
              serializer: Api::V1::ConnectionRequestSerializer,
              status: :created

      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end






      # PATCH /api/v1/requests/:id/accept
      def accept
        @connection = ConnectionRequest.pending
                        .find_by(id: params[:id], target: current_delegate)

        return render_not_found unless @connection

        ActiveRecord::Base.transaction do
          @connection.accept!

          notification = Notification.create!(
            delegate: @connection.requester,
            notification_type: 'connection_accepted',
            notifiable: @connection
          )

          # 🔥 AUDIT
          AuditLogger.connection_accepted(@connection, request)

          NotificationChannel.broadcast_to(
            @connection.requester,
            type: 'new_notification',
            notification: {
              id: notification.id,
              type: 'connection_accepted',
              created_at: notification.created_at,
              accepter: {
                id: current_delegate.id,
                name: current_delegate.name,
                avatar_url: current_delegate.avatar_url
              }
            }
          )
        end

        render json: @connection,
              serializer: Api::V1::ConnectionRequestSerializer

      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end







      
      # PATCH /api/v1/requests/:id/reject
      def reject
        @connection = ConnectionRequest.pending
                        .find_by(id: params[:id], target: current_delegate)

        return render_not_found unless @connection

        ActiveRecord::Base.transaction do
          @connection.reject!

          # 🔥 AUDIT
          AuditLogger.connection_rejected(@connection, request)
        end

        render json: {
          message: 'Connection rejected successfully',
          request: Api::V1::ConnectionRequestSerializer.new(@connection).serializable_hash
        }

      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end




      def my_received
        me = current_delegate

        requests = ConnectionRequest
          .where(target_id: me.id, status: "pending")
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
