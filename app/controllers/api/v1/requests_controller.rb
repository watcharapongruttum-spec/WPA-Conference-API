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
        @connection = ConnectionRequest.new(
          requester: current_delegate,
          target_id: params[:target_id]
        )
        
        if @connection.save
          render json: @connection, serializer: Api::V1::ConnectionRequestSerializer, status: :created
        else
          render json: { 
            error: 'Failed to create connection request', 
            errors: @connection.errors.full_messages 
          }, status: :unprocessable_entity
        end
      end
      
      # PATCH /api/v1/requests/:id/accept
      def accept
        @connection = ConnectionRequest.pending.find_by(id: params[:id], target: current_delegate)
        
        if @connection.nil?
          render json: { error: 'Connection not found or already processed' }, status: :not_found
          return
        end
        
        if @connection.accept
          render json: @connection, serializer: Api::V1::ConnectionRequestSerializer
        else
          render json: { error: 'Failed to accept connection' }, status: :unprocessable_entity
        end
      end
      
      # PATCH /api/v1/requests/:id/reject
      def reject
        @connection = ConnectionRequest.pending.find_by(id: params[:id], target: current_delegate)
        
        if @connection.nil?
          render json: { error: 'Connection not found or already processed' }, status: :not_found
          return
        end
        
        if @connection.reject
          render json: { message: 'Connection rejected' }
        else
          render json: { error: 'Failed to reject connection' }, status: :unprocessable_entity
        end
      end
    end
  end
end