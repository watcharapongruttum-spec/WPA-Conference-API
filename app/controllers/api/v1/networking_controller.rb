# app/controllers/api/v1/networking_controller.rb
module Api
  module V1
    class NetworkingController < ApplicationController

      # GET /api/v1/networking/directory
      def directory
        @delegates = Delegate.includes(:company, :team)
                             .where.not(name: [nil, ''])
                             .where.not(id: current_delegate.id)
                             .order(name: :asc)
                             .page(params[:page] || 1)
                             .per(20)

        # ✅ FIX: ส่ง scope: current_delegate เพื่อให้ is_connected ทำงานได้
        render json: @delegates,
               each_serializer: Api::V1::Networking::DirectorySerializer,
               scope: current_delegate

      rescue StandardError => e
        Rails.logger.error "Directory Error: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")

        render json: {
          error: 'Failed to load directory',
          message: Rails.env.development? ? e.message : nil
        }, status: :internal_server_error
      end

      def unfriend
        delegate_id = params[:delegate_id]
        target = Delegate.find_by(id: delegate_id)
        return render json: { error: 'Delegate not found' }, status: :not_found unless target

        connection = Connection.where(
          requester_id: [current_delegate.id, target.id]
        ).where(
          target_id: [current_delegate.id, target.id]
        ).first

        conn_request = ConnectionRequest.where(
          requester_id: [current_delegate.id, target.id]
        ).where(
          target_id: [current_delegate.id, target.id]
        ).first

        return render json: { error: 'Connection not found' }, status: :not_found \
          unless connection || conn_request

        ActiveRecord::Base.transaction do
          connection&.destroy
          conn_request&.destroy
        end

        render json: { message: 'Unfriended successfully' }, status: :ok
      end

      # GET /api/v1/networking/my_connections
      def my_connections
        @connections = Connection.accepted
                                 .where(requester: current_delegate)
                                 .or(Connection.accepted.where(target: current_delegate))
                                 .includes(:requester, :target)

        render json: @connections, each_serializer: Api::V1::Networking::ConnectionSerializer

      rescue StandardError => e
        Rails.logger.error "My Connections Error: #{e.class} - #{e.message}"
        render json: {
          error: 'Failed to load connections',
          message: Rails.env.development? ? e.message : nil
        }, status: :internal_server_error
      end

      # GET /api/v1/networking/pending_requests
      def pending_requests
        @connections = Connection.pending
                                 .where(target: current_delegate)
                                 .includes(:requester)

        render json: @connections, each_serializer: Api::V1::Networking::ConnectionSerializer

      rescue StandardError => e
        Rails.logger.error "Pending Requests Error: #{e.class} - #{e.message}"
        render json: {
          error: 'Failed to load requests',
          message: Rails.env.development? ? e.message : nil
        }, status: :internal_server_error
      end

    end
  end
end