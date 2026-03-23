# app/controllers/api/v1/admin/maintenance_controller.rb
module Api
  module V1
    module Admin
      class MaintenanceController < Api::V1::Admin::BaseController
        def clear_sidekiq
          require "sidekiq/api"

          Sidekiq::Queue.all.each(&:clear)
          Sidekiq::RetrySet.new.clear
          Sidekiq::ScheduledSet.new.clear
          Sidekiq::DeadSet.new.clear

          render json: { message: "Sidekiq queues cleared" }
        end
      end
    end
  end
end