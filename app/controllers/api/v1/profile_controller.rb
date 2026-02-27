# app/controllers/api/v1/profile_controller.rb
module Api
  module V1
    class ProfileController < BaseController
      # ==================
      # GET /api/v1/profile
      # GET /api/v1/profile/:id
      # ==================
      def show
        delegate = find_delegate
        return render_not_found unless delegate

        render json: build_profile_json(delegate)
      end

      # ==================
      # PATCH /api/v1/profile
      # อัพเดท text fields (name, title, phone, ...)
      # ==================
      def update
        if current_delegate.update(profile_params)
          render json: build_profile_json(current_delegate)
        else
          render json: {
            success: false,
            errors: current_delegate.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # ==================
      # PATCH /api/v1/profile/avatar
      # อัพเดทรูปภาพอย่างเดียว
      # รับได้ทั้ง multipart/form-data และ application/json (base64)
      # ==================
      def update_avatar
        if params[:avatar].blank?
          return render json: { error: "Avatar is required" },
                        status: :unprocessable_entity
        end

        result = attach_avatar(params[:avatar])

        if result[:success]
          render json: {
            success: true,
            avatar_url: current_delegate.avatar_url
          }
        else
          render json: {
            success: false,
            error: result[:error]
          }, status: :unprocessable_entity
        end
      end

      private

      # ==================
      # Avatar Handler
      # รองรับทั้ง multipart และ base64
      # ==================
      def attach_avatar(avatar_param)
        # กรณี multipart/form-data — ได้ UploadedFile มาตรง ๆ
        if avatar_param.respond_to?(:content_type)
          return validate_and_attach(
            io: avatar_param,
            content_type: avatar_param.content_type,
            filename: avatar_param.original_filename
          )
        end

        # กรณี application/json — base64 string
        if avatar_param.is_a?(String) && avatar_param.include?("base64,")
          match = avatar_param.match(%r{\Adata:([-\w]+/[-\w+]+)?;base64,(.*)}m)
          return { success: false, error: "Invalid base64 format" } unless match

          content_type = match[1] || "image/jpeg"
          decoded      = Base64.decode64(match[2])
          extension    = content_type.split("/").last.gsub("jpeg", "jpg")

          return validate_and_attach(
            io: StringIO.new(decoded),
            content_type: content_type,
            filename: "avatar_#{current_delegate.id}.#{extension}",
            size: decoded.bytesize
          )
        end

        { success: false, error: "Invalid avatar format" }
      rescue StandardError => e
        Rails.logger.error "[ProfileController#attach_avatar] #{e.message}"
        { success: false, error: "Failed to process image" }
      end

      def validate_and_attach(io:, content_type:, filename:, size: nil)
        # เช็ค content type
        allowed = %w[image/jpeg image/jpg image/png image/webp]
        return { success: false, error: "Only JPEG, PNG, WebP allowed" } unless allowed.include?(content_type)

        # เช็ค size (ถ้ามี — multipart เช็คจาก .size, base64 ส่ง size มาเอง)
        file_size = size || (io.respond_to?(:size) ? io.size : 0)
        return { success: false, error: "Image must be less than 5MB" } if file_size > 5.megabytes

        # ลบรูปเก่าก่อน
        current_delegate.avatar.purge if current_delegate.avatar.attached?

        # attach ใหม่
        current_delegate.avatar.attach(
          io: io,
          filename: filename,
          content_type: content_type
        )

        { success: true }
      end

      # ==================
      # Helpers
      # ==================
      def find_delegate
        if params[:id].present?
          Delegate.includes(:company, :team).find_by(id: params[:id])
        else
          current_delegate
        end
      end

      def render_not_found
        render json: { error: "Not found" }, status: :not_found
      end

      def profile_params
        params.permit(
          :name,
          :title,
          :phone,
          :spouse_attending,
          :spouse_name,
          :need_room,
          :booking_no
        )
      end

      def build_profile_json(delegate)
        company = delegate.company
        team    = delegate.team
        {
          id: delegate.id,
          name: delegate.name,
          title: delegate.title,
          email: delegate.email,
          phone: delegate.phone,
          avatar_url: delegate.avatar_url,
          company: company && {
            id: company.id,
            name: company.name,
            country: company.country
          },
          team: team && {
            id: team.id,
            name: team.name,
            country_code: team.country_code
          },
          first_conference: delegate.first_conference,
          spouse_attending: delegate.spouse_attending,
          spouse_name: delegate.spouse_name,
          need_room: delegate.need_room,
          booking_no: delegate.booking_no
        }
      end
    end
  end
end
