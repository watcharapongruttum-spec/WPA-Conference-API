# Rails.application.routes.draw do
#   root to: proc { [200, { 'Content-Type' => 'application/json' }, [{ status: 'ok' }.to_json]] }
#   mount ActionCable.server => '/cable'
  
#   namespace :api do
#     namespace :v1 do
#       post 'reset_password', to: 'sessions#reset_password'
#       get "/reset-password", to: "deeplink#reset_password"

#       # routes.rb
#       post 'messages/read_all', to: 'messages#read_all'
#       patch 'change_password', to: 'passwords#change'


      
#       # Profile
#       get 'profile(/:id)', to: 'profile#show'
#       patch 'profile', to: 'profile#update'
#       patch  'device_token', to: 'devices#update'
#       get :dashboard, to: 'dashboard#show'
      
#       # Authentication
#       post 'login', to: 'sessions#create'
#       post 'change_password', to: 'sessions#change_password'
#       post 'forgot_password', to: 'sessions#forgot_password'
      
#       # Delegates
#       resources :delegates, only: [:index, :show] do
#         collection do
#           get :search
#         end
#         member do
#           get :qr_code
#         end
#       end
      
#       # Schedules
#       resources :schedules, only: [:index, :create] do
#         collection do
#           get :my_schedule
#           get :schedule_others
#         end
#       end
      
#       # Tables
#       resources :tables, only: [:show] do
#         collection do
#           get :grid_view
#           get :time_view
#         end
#       end
      
#       # ===== MESSAGES (แก้ route conversation) =====
#       resources :messages, only: [:index, :create, :update, :destroy] do
#         collection do
#           # ⭐ แก้ route ให้ตรงกับ test
#           # get 'conversation/:delegate_id', to: 'messages#conversation', as: :conversation
#           get 'conversation/:delegate_id', to: 'messages#conversation'
#           get :rooms
#           patch :read_all
#           get :unread_count
#           get :online_status
#         end
#         member do
#           patch :mark_as_read
#         end
#       end
      
#       # Networking
#       # get 'networking/directory', to: 'networking#directory'
#       # get 'networking/my_connections', to: 'networking#my_connections'
#       # get 'networking/pending_requests', to: 'networking#pending_requests'
#       # delete 'networking/unfriend/:delegate_id', to: 'networking#unfriend'

#       # Networking
#       resources :networking, only: [] do
#         collection do
#           get :directory
#           get :my_connections
#           get :pending_requests
#           delete 'unfriend/:delegate_id', to: 'api/v1/networking#unfriend'
#         end
#       end


      
      
#       # Requests
#       resources :requests, only: [:index, :create] do
#         collection do
#           get :my_received
#         end
#         member do
#           patch :accept
#           patch :reject
#         end
#       end
      
#       # Chat Rooms
#       resources :chat_rooms, only: [:index, :create, :destroy] do
#         member do
#           post :join
#           delete :leave
#         end
#       end
      
#       # Notifications
#       resources :notifications, only: [:index] do
#         collection do
#           get :unread_count
#           patch :mark_all_as_read
#         end
#         member do
#           patch :mark_as_read
#         end
#       end
      
#       # Leave Forms
#       resources :leave_forms, only: [:create]
#       resources :leave_types
#     end
#   end
# end







Rails.application.routes.draw do
  root to: proc { [200, { 'Content-Type' => 'application/json' }, [{ status: 'ok' }.to_json]] }
  mount ActionCable.server => '/cable'

  namespace :api do
    namespace :v1 do

      # Deeplink
      get '/reset-password', to: 'deeplink#reset_password'

      # Authentication
      controller :sessions do
        post :login,           action: :create
        post :forgot_password
        post :reset_password
      end

      # Change Password (แยกออกมา + เปลี่ยนเป็น PATCH ให้ตรงกับ test)
      patch 'change_password', to: 'sessions#change_password'

      # Profile
      get   'profile(/:id)', to: 'profile#show'
      patch 'profile',       to: 'profile#update'

      # Device token
      patch 'device_token', to: 'devices#update'

      # Dashboard
      get 'dashboard', to: 'dashboard#show'

      # Delegates (profile collection ต้องอยู่ก่อน member ไม่งั้น :id match "profile" ก่อน)
      resources :delegates, only: [:index, :show] do
        collection do
          get :profile   # ← เพิ่ม /delegates/profile
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
          get :time_view
        end
      end

      # Messages
      resources :messages, only: [:index, :create, :update, :destroy] do
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

      # Requests (cancel เพิ่มเพื่อให้ cleanup_connection ใน test ทำงานได้)
      resources :requests, only: [:index, :create] do
        collection do
          get :my_received
        end
        member do
          patch  :accept
          patch  :reject
          delete :cancel   # ← เพิ่ม
        end
      end

      # Chat Rooms
      resources :chat_rooms, only: [:index, :create, :destroy] do
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