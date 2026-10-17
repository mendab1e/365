# frozen_string_literal: true

module YearInPhotos
  module BotCommands
    private

    def dispatch_message(message)
      file_id = image_file_id(message)
      return receive_photo(file_id, message_date(message)) if file_id
      return reply("Only JPEG/JPG and HEIC image documents are accepted.") if message["document"]

      case command_name(message)
      when "/status" then send_status
      when "/rebuild" then rebuild
      when "/yesterday" then select_yesterday(message_date(message))
      when "/cancel" then cancel_selection
      else reply("Send today’s photo as an image or image file. " \
                 "Commands: /status, /rebuild, /yesterday, /cancel")
      end
    end

    def select_yesterday(date)
      @write_lock.synchronize { @next_photo_date = date - 1 }
      reply("Send the photo for #{(date - 1).strftime('%B %-d, %Y')}. " \
            "It will replace any photo for that date. Use /cancel to return to today.")
    end

    def cancel_selection
      @write_lock.synchronize { @next_photo_date = nil }
      reply("Cancelled. The next photo will be published for today.")
    end

    def rebuild
      @write_lock.synchronize { @generator.generate! }
      reply("Site rebuilt.")
    end

    def send_status
      text = @write_lock.synchronize do
        today = @clock.now.to_date
        photos = @store.photos
        published = photos.any? { |photo| photo.fetch(:date) == today.iso8601 }
        status = published ? "published" : "still missing"
        "Today’s photo is #{status}. #{photos.length} photo(s) published in total."
      end
      reply(text)
    end

    def command_name(message)
      token = message["text"].to_s.split.first
      token&.split("@", 2)&.first
    end
  end
end
