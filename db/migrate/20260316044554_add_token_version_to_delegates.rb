# db/migrate/XXXXXX_add_token_version_to_delegates.rb
class AddTokenVersionToDelegates < ActiveRecord::Migration[7.0]
  def change
    add_column :delegates, :token_version, :integer, default: 1, null: false
  end
end