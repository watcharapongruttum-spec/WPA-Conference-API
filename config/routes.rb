Rails.application.routes.draw do
  root to: proc { [200, { 'Content-Type' => 'application/json' }, [{ status: 'ok' }.to_json]] }
  mount ActionCable.server => '/cable'
  get "/reset-password", to: redirect { |params, request|
    "wpaapp://reset-password?token=#{params[:token]}"
  }




  namespace :api do
    namespace :v1 do



      namespace :admin do
        get "clear_sidekiq", to: "maintenance#clear_sidekiq"
      end



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