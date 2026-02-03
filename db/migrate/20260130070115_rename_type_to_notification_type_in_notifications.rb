# db/migrate/XXXXXX_rename_type_to_notification_type_in_notifications.rb
class RenameTypeToNotificationTypeInNotifications < ActiveRecord::Migration[7.0]
  def change
    rename_column :notifications, :type, :notification_type
  end
end