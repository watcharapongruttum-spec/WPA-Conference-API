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
        # 🔥 FIX: Validate target_id
        unless params[:target_id].present?
          render json: { 
            error: 'Target ID is required',
            hint: 'Use target_id parameter'
          }, status: :unprocessable_entity
          return
        end
        
        # 🔥 FIX: Check if target exists
        target = Delegate.find_by(id: params[:target_id])
        
        unless target
          render json: { 
            error: 'Target delegate not found' 
          }, status: :not_found
          return
        end
        
        # 🔥 FIX: Check if trying to connect to self
        if params[:target_id].to_i == current_delegate.id
          render json: { 
            error: 'Cannot send connection request to yourself' 
          }, status: :unprocessable_entity
          return
        end
        
        # 🔥 FIX: Check if connection already exists
        existing = ConnectionRequest.find_by(
          requester_id: current_delegate.id,
          target_id: params[:target_id]
        )
        
        if existing
          render json: { 
            error: 'Connection request already exists',
            status: existing.status,
            request: Api::V1::ConnectionRequestSerializer.new(existing).serializable_hash
          }, status: :unprocessable_entity
          return
        end
        
        @connection = ConnectionRequest.new(
          requester: current_delegate,
          target_id: params[:target_id]
        )
        
        if @connection.save
          # 🔥 Create notification for target
          notification = Notification.create!(
            delegate: @connection.target,
            notification_type: 'connection_request',
            notifiable: @connection
          )
          
          # 🔥 Broadcast notification
          NotificationChannel.broadcast_to(
            @connection.target,
            type: 'new_notification',
            notification: {
              id: notification.id,
              type: 'connection_request',
              created_at: notification.created_at,
              requester: {
                id: current_delegate.id,
                name: current_delegate.name,
                avatar_url: Api::V1::DelegateSerializer.new(current_delegate).avatar_url
              }
            }
          )
          
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
        # 🔥 FIX: Only target can accept
        @connection = ConnectionRequest.pending.find_by(id: params[:id], target: current_delegate)
        
        if @connection.nil?
          # Check if request exists but wrong user
          wrong_user = ConnectionRequest.find_by(id: params[:id])
          
          if wrong_user
            render json: { 
              error: 'Only the target of the connection request can accept it',
              hint: 'You must be the person who received this request'
            }, status: :forbidden
            return
          else
            render json: { 
              error: 'Connection request not found or already processed' 
            }, status: :not_found
            return
          end
        end
        
        if @connection.accept
          # 🔥 Notify requester
          notification = Notification.create!(
            delegate: @connection.requester,
            notification_type: 'connection_accepted',
            notifiable: @connection
          )
          
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
                avatar_url: Api::V1::DelegateSerializer.new(current_delegate).avatar_url
              }
            }
          )
          
          render json: @connection, serializer: Api::V1::ConnectionRequestSerializer
        else
          render json: { 
            error: 'Failed to accept connection',
            errors: @connection.errors.full_messages
          }, status: :unprocessable_entity
        end
      end
      
      # PATCH /api/v1/requests/:id/reject
      def reject
        # 🔥 FIX: Only target can reject
        @connection = ConnectionRequest.pending.find_by(id: params[:id], target: current_delegate)
        
        if @connection.nil?
          # Check if request exists but wrong user
          wrong_user = ConnectionRequest.find_by(id: params[:id])
          
          if wrong_user
            render json: { 
              error: 'Only the target of the connection request can reject it',
              hint: 'You must be the person who received this request'
            }, status: :forbidden
            return
          else
            render json: { 
              error: 'Connection request not found or already processed' 
            }, status: :not_found
            return
          end
        end
        
        if @connection.reject
          render json: { 
            message: 'Connection rejected successfully',
            request: Api::V1::ConnectionRequestSerializer.new(@connection).serializable_hash
          }
        else
          render json: { 
            error: 'Failed to reject connection',
            errors: @connection.errors.full_messages
          }, status: :unprocessable_entity
        end
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










    end
  end
end
