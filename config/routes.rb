Rails.application.routes.draw do
  mount ActionCable.server => '/cable'

  namespace :api do
    namespace :v1 do




      get :dashboard, to: 'dashboard#show'



      # Authentication
      post 'login', to: 'sessions#create'
      post 'change_password', to: 'sessions#change_password'
      post 'forgot_password', to: 'sessions#forgot_password'

      # Profile
      get 'profile', to: 'profile#show'

      # Delegates
      resources :delegates, only: [:index, :show] do
        collection do
          get :search
        end

        member do
          get :qr_code
        end


      end

      # Schedules
      resources :schedules, only: [:index, :create] do
        collection do
          get :my_schedule
          get :schedule_others 
        end
      end

      # Tables
      resources :tables, only: [:show] do
        collection do
          get :grid_view
        end
      end

      # Messages
      resources :messages, only: [:index, :create] do
        collection do
          get 'conversation/:delegate_id', to: 'messages#conversation'
          get :rooms
        end
        member do
          patch :mark_as_read
        end
      end

      # Networking
      get 'networking/directory', to: 'networking#directory'
      get 'networking/my_connections', to: 'networking#my_connections'
      get 'networking/pending_requests', to: 'networking#pending_requests'

      # Requests
      resources :requests, only: [:index, :create] do
        
        collection do
          get :my_received
        end

        member do
          patch :accept
          patch :reject
        end
      end

      # Chat Rooms
      resources :chat_rooms, only: [:index, :create]

      # Notifications
      resources :notifications, only: [:index] do
        collection do
          get :unread_count
          patch :mark_all_as_read
        end
        member do
          patch :mark_as_read
        end
      end
    end
  end
end
