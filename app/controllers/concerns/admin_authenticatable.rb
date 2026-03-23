# app/controllers/concerns/admin_authenticatable.rb
module AdminAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_admin!
  end

  private

  def authenticate_admin!
    token = request.headers["X-Admin-Token"]
    render json: { error: "Unauthorized" }, status: :unauthorized unless token == ENV["ADMIN_TOKEN"]
  end
end