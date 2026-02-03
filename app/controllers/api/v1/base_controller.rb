# app/controllers/api/v1/base_controller.rb
module Api
  module V1
    class BaseController < ApplicationController
      # include ActionController::Serialization
      # rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
      # rescue_from ActionController::ParameterMissing, with: :missing_params


      
      # private
      
      # def record_not_found
      #   render json: { error: 'Record not found' }, status: :not_found
      # end
      
      # def missing_params(exception)
      #   render json: { error: "Missing parameter: #{exception.param}" }, status: :bad_request
      # end
      
      # # ดึงข้อมูลผู้ใช้ปัจจุบันจากโทเค็น JWT
      # def current_delegate
      #   @current_delegate ||= begin
      #     token = request.headers['Authorization']&.split(' ')&.last
      #     return nil if token.blank?
          
      #     begin
      #       decoded = JWT.decode(token, JWT_SECRET, true, algorithm: JWT_CONFIG[:algorithm])
      #       delegate_id = decoded[0]['delegate_id']
      #       Delegate.find(delegate_id)
      #     rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      #       nil
      #     end
      #   end
      # end
      
      # # ตรวจสอบโทเค็น
      # def authenticate_delegate
      #   unless current_delegate
      #     render json: { error: 'Authentication required' }, status: :unauthorized
      #     return false
      #   end
      #   true
      # end
      
      # # สร้างโทเค็น JWT
      # def generate_jwt_token(delegate)
      #   payload = {
      #     delegate_id: delegate.id,
      #     exp: JWT_CONFIG[:expiration_time].seconds.from_now.to_i,
      #     iss: JWT_CONFIG[:issuer]
      #   }
        
      #   JWT.encode(payload, JWT_SECRET, JWT_CONFIG[:algorithm])
      # end


    end
  end
end