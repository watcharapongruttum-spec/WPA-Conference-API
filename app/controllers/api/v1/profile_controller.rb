# app/controllers/api/v1/profile_controller.rb
module Api
  module V1
    class ProfileController < BaseController

      def show
        delegate = find_delegate
        return render_not_found unless delegate

        render json: build_profile_json(delegate)
      end

      def update
        # ✅ FIX: handle avatar attachment แยกต่างหาก
        if params[:avatar].present?
          current_delegate.avatar.attach(params[:avatar])
        end

        if current_delegate.update(profile_params)
          render json: build_profile_json(current_delegate)
        else
          render json: {
            success: false,
            errors: current_delegate.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      private

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

      # ✅ FIX: เพิ่ม :avatar ใน strong params
      def profile_params
        params.permit(
          :name,
          :title,
          :phone,
          :spouse_attending,
          :spouse_name,
          :need_room,
          :booking_no
          # :avatar ไม่ใส่ตรงนี้ เพราะ ActiveStorage ต้องใช้ .attach() แยก
        )
      end

      # ✅ FIX: ใช้ avatar จริงถ้ามี ถ้าไม่มีค่อย fallback
      def build_profile_json(delegate)
        company = delegate.company
        team = delegate.team

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