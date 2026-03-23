# app/controllers/api/v1/admin/dashboard_controller.rb
module Api
  module V1
    module Admin
      class DashboardController < Api::V1::Admin::BaseController
        def show
          render json: {
            delegates: {
              total:        Delegate.count,
              logged_in:    Delegate.where(has_logged_in: true).count,
              never_logged: Delegate.where(has_logged_in: false).count,
              has_device:   Delegate.where.not(device_token: nil).count
            },
            announcements: {
              total: Announcement.count,
              latest: Announcement.order(sent_at: :desc).limit(1).pick(:sent_at)&.iso8601
            },
            leave_forms: {
              total:    LeaveForm.count,
              reported: LeaveForm.where(status: "reported").count,
              approved: LeaveForm.where(status: "approved").count,
              rejected: LeaveForm.where(status: "rejected").count
            },
            group_chats: {
              total:   ChatRoom.where(room_kind: :group, deleted_at: nil).count,
              deleted: ChatRoom.where(room_kind: :group).where.not(deleted_at: nil).count
            },
            notifications: {
              total:  Notification.count,
              unread: Notification.where(read_at: nil).count
            }
          }
        end
      end
    end
  end
end
