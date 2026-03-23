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







        def sidekiq_status
          require "sidekiq/api"

          stats = Sidekiq::Stats.new

          queues = Sidekiq::Queue.all.map do |q|
            { name: q.name, size: q.size, latency: q.latency.round(2) }
          end

          render json: {
            overview: {
              processed:   stats.processed,
              failed:      stats.failed,
              enqueued:    stats.enqueued,
              scheduled:   stats.scheduled_size,
              retry:       stats.retry_size,
              dead:        stats.dead_size,
              workers:     stats.workers_size,
              processes:   stats.processes_size
            },
            queues: queues
          }
        end


        def redis_status
          info = REDIS.info

          render json: {
            version:            info["redis_version"],
            uptime_days:        info["uptime_in_days"].to_i,
            connected_clients:  info["connected_clients"].to_i,
            memory_used:        info["used_memory_human"],
            memory_peak:        info["used_memory_peak_human"],
            total_commands:     info["total_commands_processed"].to_i,
            total_connections:  info["total_connections_received"].to_i,
            keyspace:           info.select { |k, _| k.start_with?("db") }
          }
        rescue StandardError => e
          render json: { error: e.message }, status: :internal_server_error
        end






        def export_csv
          require "csv"

          delegates = Delegate.includes(:company, :team).order(:name)

          csv_data = CSV.generate(headers: true) do |csv|
            csv << %w[id name email title phone company country team has_logged_in first_login_at]

            delegates.each do |d|
              csv << [
                d.id,
                d.name,
                d.email,
                d.title,
                d.phone,
                d.company&.name,
                d.company&.country,
                d.team&.name,
                d.has_logged_in,
                d.first_login_at&.iso8601
              ]
            end
          end

          send_data csv_data,
                    filename:    "delegates_#{Date.today}.csv",
                    type:        "text/csv",
                    disposition: "attachment"
        end












      end
    end
  end
end

