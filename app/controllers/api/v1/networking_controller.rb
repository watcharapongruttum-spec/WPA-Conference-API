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

        render json: @delegates, each_serializer: Api::V1::Networking::DirectorySerializer
      rescue StandardError => e
        Rails.logger.error "Directory Error: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        
        render json: { 
          error: 'Failed to load directory',
          message: Rails.env.development? ? e.message : nil
        }, status: :internal_server_error
      end



      
      def unfriend
        friend = Delegate.find(params[:delegate_id])

        connection = Connection.find_by(requester: current_delegate, target: friend) ||
                    Connection.find_by(requester: friend, target: current_delegate)

        if connection
          connection.destroy
          render json: { success: true, message: "Unfriended successfully" }
        else
          render json: { error: "Connection not found" }, status: :not_found
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Delegate not found" }, status: :not_found
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
        Rails.logger.error e.backtrace.first(10).join("\n")
        
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
        Rails.logger.error e.backtrace.first(10).join("\n")
        
        render json: { 
          error: 'Failed to load requests',
          message: Rails.env.development? ? e.message : nil
        }, status: :internal_server_error
      end

    end
  end
end