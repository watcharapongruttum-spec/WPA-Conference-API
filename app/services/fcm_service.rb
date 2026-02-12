class FcmService
  def self.send_push(token:, title:, body:, data: {})
    return if token.blank?

    fcm = FCM.new(ENV['FCM_SERVER_KEY'])

    options = {
      notification: {
        title: title,
        body: body
      },
      data: data
    }

    fcm.send([token], options)
  end
end
