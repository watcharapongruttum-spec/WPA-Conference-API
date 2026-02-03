# app/models/user.rb
class User < ApplicationRecord
  has_secure_password
  has_one :delegate_profile, class_name: 'Delegate', foreign_key: 'id', primary_key: 'id'
  
  def auth_token
    Knock::AuthToken.new(payload: { sub: id }).token
  end
end


