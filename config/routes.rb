Rails.application.routes.draw do
  root to: proc { [200, { 'Content-Type' => 'application/json' }, [{ status: 'ok' }.to_json]] }
  mount ActionCable.server => '/cable'

  get  '/deeplink-reset-password',               to: 'api/v1/deeplink#reset_password'
  post '/api/v1/deeplink/reset_password_submit', to: 'api/v1/deeplink#reset_password_submit'


  namespace :api do
    namespace :v1 do
      scope '/group_chat', controller: 'group_chat' do
        get    '/',                           action: :index,        as: :group_chat_rooms
        post   '/',                           action: :create_room,  as: :group_chat_create_room
        post   '/:id/join',                   action: :join,         as: :group_chat_join
        delete '/:id/leave',                  action: :leave,        as: :group_chat_leave
        delete '/:id',                        action: :destroy_room, as: :group_chat_destroy_room
        get    '/:id/messages',               action: :messages,     as: :group_chat_messages
        post   '/:id/messages',               action: :send_message, as: :group_chat_send_message
        get    '/:id/messages/:message_id/readers', action: :readers, as: :group_chat_readers
      end






      # namespace :admin do
      #   get 'clear_sidekiq', to: 'maintenance#clear_sidekiq'
      #   post 'announcements', to: 'announcements#create'
      # end


      # config/routes.rb
      namespace :admin do
        get  "clear_sidekiq",            to: "maintenance#clear_sidekiq"
        post "announcements",            to: "announcements#create"
        get  "announcements",            to: "announcements#index"
        get  "delegates",                to: "delegates#index"
        get  "delegates/:id",            to: "delegates#show"
        post "delegates/:id/reset_password", to: "delegates#reset_password"
        get  "audit_logs",               to: "audit_logs#index"
        get  "leave_forms",              to: "leave_forms#index"
        get  "group_chats",              to: "group_chats#index"
        get  "group_chats/:id",          to: "group_chats#show"
        get  "dashboard",                to: "dashboard#show"


        get "security_logs",       to: "security_logs#index"
        get "tables/time_view",    to: "tables#time_view"
        get "notifications",       to: "notifications#index"
        get "connection_requests", to: "connection_requests#index"



      end









      # Deeplink
      get '/reset-password', to: 'deeplink#reset_password'

      # Authentication
      controller :sessions do
        post :login, action: :create
        post :forgot_password
        post :reset_password
      end

      # Change Password
      patch 'change_password', to: 'sessions#change_password'

      # Profile
      get   'profile(/:id)', to: 'profile#show'
      patch 'profile',       to: 'profile#update'
      patch 'profile/avatar', to: 'profile#update_avatar'

      # Device token
      patch 'device_token', to: 'devices#update'

      # Dashboard
      get 'dashboard', to: 'dashboard#show'

      # Delegates
      resources :delegates, only: %i[index show] do
        member do
          get :qr_code
        end
        collection do
          get :me 
        end
      end

      # Schedules
      resources :schedules, only: %i[] do
        collection do
          get :my_schedule
          get :schedule_others
        end
      end

      # Tables
      resources :tables, only: [] do
        collection do
          # get :grid_view
          get :time_view
        end
      end

      # Messages
      resources :messages, only: %i[index create update destroy] do
        collection do
          get    'conversation/:delegate_id', to: 'messages#conversation'
          delete 'conversation/:delegate_id', to: 'messages#clear_conversation'
          get    :rooms
          patch  :read_all
          get    :unread_count
          get    :online_status
        end
        member do
          patch :mark_as_read
        end
      end

      # Networking
      resources :networking, only: [] do
        collection do
          get    :directory
          get    :my_connections
          get    :pending_requests
          delete 'unfriend/:delegate_id', action: :unfriend
        end
      end

      # Requests
      resources :requests, only: %i[index create] do
        collection do
          get :my_received
        end
        member do
          patch  :accept
          patch  :reject
          delete :cancel
        end
      end

      # Chat Rooms
      # Notifications
      resources :chat_rooms, only: %i[index create destroy] do
        member do
          post   :join
          delete :leave
        end
      end

      resources :notifications, only: [:index] do
        collection do
          get   :unread_count
          patch :mark_all_as_read
        end
        member do
          patch :mark_as_read
        end
      end

      # Leave Forms
      resources :leave_forms, only: [:create]
      resources :leave_types
    end
  end
end