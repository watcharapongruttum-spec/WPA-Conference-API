# app/controllers/api/v1/profile_controller.rb
module Api
  module V1
    class ProfileController < BaseController
      # app/controllers/api/v1/profile_controller.rb
      def show
        delegate = current_delegate
        render json: {
          id: delegate.id,
          name: delegate.name,
          title: delegate.title,
          email: delegate.email,
          phone: delegate.phone,
          company: {
            id: delegate.company.id,
            name: delegate.company.name,
            country: delegate.company.country,
            logo_url: nil
          },
          # ใช้ fallback avatar เสมอ
          avatar_url: "https://ui-avatars.com/api/?name=#{CGI.escape(delegate.name)}&background=0D8ABC&color=fff",
          team: delegate.team ? {
            id: delegate.team.id,
            name: delegate.team.name,
            country_code: delegate.team.country_code
          } : nil,
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