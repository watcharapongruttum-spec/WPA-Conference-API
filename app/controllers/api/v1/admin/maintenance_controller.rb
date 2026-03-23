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

        # ล้าง Notifications ทั้งหมด
        def reset_notifications
          count = Notification.count
          Notification.delete_all
          render json: {
            success: true,
            message: "Notifications cleared",
            deleted_count: count
          }
        end

        # ล้าง Messages ทั้งหมด (chat + group)
        def reset_messages
          messages_count = ChatMessage.count
          reads_count    = MessageRead.count

          MessageRead.delete_all
          ChatMessage.delete_all

          render json: {
            success: true,
            message: "Messages cleared",
            deleted: {
              chat_messages:  messages_count,
              message_reads:  reads_count
            }
          }
        end

        # ล้าง Logs ทั้งหมด (audit + security)
        def reset_logs
          audit_count    = AuditLog.count
          security_count = SecurityLog.count

          AuditLog.delete_all
          SecurityLog.delete_all

          render json: {
            success: true,
            message: "Logs cleared",
            deleted: {
              audit_logs:    audit_count,
              security_logs: security_count
            }
          }
        end

        # ล้างทุกอย่างพร้อมกัน
        def reset_all
          counts = {
            notifications:  Notification.count,
            chat_messages:  ChatMessage.count,
            message_reads:  MessageRead.count,
            audit_logs:     AuditLog.count,
            security_logs:  SecurityLog.count,
            announcements:  Announcement.count
          }

          Notification.delete_all
          MessageRead.delete_all
          ChatMessage.delete_all
          AuditLog.delete_all
          SecurityLog.delete_all
          Announcement.delete_all

          render json: {
            success: true,
            message: "System reset complete",
            deleted: counts
          }
        end
      end
    end
  end
end

