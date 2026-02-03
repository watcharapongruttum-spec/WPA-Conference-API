# config/routes.rb
Rails.application.routes.draw do
  mount ActionCable.server => '/cable'

  
  namespace :api do
    namespace :v1 do
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
      end
      
      # Schedules
      resources :schedules, only: [:index, :create] do
        collection do
          get :my_schedule
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
          get 'conversation/:delegate_id', to: 'messages#conversation', as: 'conversation'
        end
        member do
          patch :mark_as_read
        end
      end
      
      # Networking
      # namespace :networking do
      #   get 'directory', to: 'networking#directory'
      #   get 'my_connections', to: 'networking#my_connections'
      #   get 'pending_requests', to: 'networking#pending_requests'
      # end


      get 'networking/directory', to: 'networking#directory'
      get 'networking/my_connections', to: 'networking#my_connections'
      get 'networking/pending_requests', to: 'networking#pending_requests'

      
      # Connection Requests
      resources :requests, only: [:index, :create] do
        member do
          patch :accept
          patch :reject
        end
      end

      resources :chat_rooms, only: [:index]

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