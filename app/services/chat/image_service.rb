# app/services/chat/image_service.rb
module Chat
  class ImageService
    ALLOWED_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
    MAX_SIZE = 5.megabytes

    # ==========================
    # attach base64 image → message
    # ==========================
    # data_uri format: "data:image/jpeg;base64,/9j/4AAQ..."
    def self.attach(message:, data_uri:)
      content_type, base64_data = parse_data_uri(data_uri)

      raise ArgumentError, "Unsupported image type: #{content_type}" unless ALLOWED_TYPES.include?(content_type)

      binary = Base64.decode64(base64_data)

      raise ArgumentError, "Image too large (max 5MB)" if binary.bytesize > MAX_SIZE

      ext      = content_type.split("/").last
      filename = "chat_image_#{SecureRandom.hex(8)}.#{ext}"

      message.image.attach(
        io:           StringIO.new(binary),
        filename:     filename,
        content_type: content_type
      )

      message
    end

    # ==========================
    # PRIVATE
    # ==========================
    def self.parse_data_uri(data_uri)
      match = data_uri.match(/\Adata:(image\/\w+);base64,(.+)\z/m)
      raise ArgumentError, "Invalid data URI format" unless match

      [match[1], match[2]]
    end
    private_class_method :parse_data_uri
  end
end