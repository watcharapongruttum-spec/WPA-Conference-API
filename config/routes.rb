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

      namespace :admin do
        get 'clear_sidekiq', to: 'maintenance#clear_sidekiq'
        post 'announcements', to: 'announcements#create'
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
        collection do
          get :profile
        end
        member do
          get :qr_code
        end
      end

      # Schedules
      resources :schedules, only: %i[index create] do
        collection do
          get :my_schedule
          get :schedule_others
        end
      end

      # Tables
      resources :tables, only: [:show] do
        collection do
          get :grid_view
          get :time_view
        end
      end

      # Messages
      resources :messages, only: %i[index create update destroy] do
        collection do
          get  'conversation/:delegate_id', to: 'messages#conversation'
          get  :rooms
          patch :read_all
          get  :unread_count
          get  :online_status
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
      resources :chat_rooms, only: %i[index create destroy] do
        member do
          post   :join
          delete :leave
        end
      end

      # Notifications
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
