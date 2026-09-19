# frozen_string_literal: true

require "date"
require "logger"
require "tempfile"

module YearInPhotos
  class Bot
    Services = Data.define(:generator, :processor, :telegram)

    POLL_RETRY_SECONDS = 5
    REMINDER_CHECK_SECONDS = 30
    NOTIFICATION_HOUR = 22
    LATE_NOTIFICATION_HOUR = 23
    LATE_NOTIFICATION_MINUTE = 59

    def initialize(config:, store:, services:, clock: Time, logger: nil)
      @config = config
      @store = store
      @generator = services.generator
      @processor = services.processor
      @telegram = services.telegram
      @clock = clock
      @logger = logger || Logger.new($stdout)
      @write_lock = Mutex.new
    end

    def run
      @logger.info("Starting bot for chat #{@config.telegram_chat_id}")
      reminder_thread = Thread.new { reminder_loop }
      poll_loop
    ensure
      reminder_thread&.kill
      reminder_thread&.join
    end

    def handle_update(update)
      message = update["message"]
      return unless authorized?(message)

      dispatch_message(message)
    rescue StandardError => e
      @logger.error("Update failed: #{e.class}: #{e.message}")
      reply("I couldn’t process that photo: #{e.message}")
    end

    def check_reminder(now = @clock.now)
      date = now.to_date
      return if now.hour < @config.reminder_hour
      return if @store.photo_on(date) || @store.reminded?(date)

      reply("It’s after #{@config.reminder_hour}:00 and today’s photo is still missing 📷")
      @store.mark_reminded(date)
    end

    def check_notification(now = @clock.now)
      return unless @config.notification_chat_id

      date = now.to_date
      return if @store.notification_published?(date)
      return if minutes_since_midnight(now) < NOTIFICATION_HOUR * 60

      if late_notification_time?(now)
        publish_notification_if_ready(date)
      else
        schedule_notification(date)
      end
    end

    private

    def dispatch_message(message)
      file_id = image_file_id(message)
      return receive_photo(file_id) if file_id

      case message["text"]&.split&.first
      when "/status" then send_status
      when "/rebuild" then rebuild
      else reply("Send today’s photo as an image or image file. Commands: /status, /rebuild")
      end
    end

    def rebuild
      @generator.generate!
      reply("Site rebuilt.")
    end

    def poll_loop
      offset = nil
      loop do
        @telegram.updates(offset:).each do |update|
          offset = update.fetch("update_id") + 1
          handle_update(update)
        end
      rescue StandardError => e
        @logger.error("Polling failed: #{e.class}: #{e.message}")
        sleep(POLL_RETRY_SECONDS)
      end
    end

    def reminder_loop
      loop do
        now = @clock.now
        check_reminder(now)
        check_notification(now)
        sleep(REMINDER_CHECK_SECONDS)
      rescue StandardError => e
        @logger.error("Reminder failed: #{e.class}: #{e.message}")
        sleep(POLL_RETRY_SECONDS)
      end
    end

    def receive_photo(file_id)
      date = @clock.now.to_date
      file_path = @telegram.file_path(file_id)
      Tempfile.create(["telegram-photo", File.extname(file_path)]) do |source|
        @telegram.download(file_path, source)
        @write_lock.synchronize do
          photo = @processor.process(source.path, date)
          @store.save_photo(photo)
          @generator.generate!
        end
      end
      reply("Published #{date.strftime('%B %-d, %Y')} ✓")
    end

    def send_status
      today = @clock.now.to_date
      status = @store.photo_on(today) ? "published" : "still missing"
      reply("Today’s photo is #{status}. #{@store.photos.length} photo(s) published in total.")
    end

    def authorized?(message)
      return false unless message
      return false unless message.dig("chat", "id").to_s == @config.telegram_chat_id

      user_id = @config.telegram_user_id
      user_id.nil? || message.dig("from", "id").to_s == user_id
    end

    def image_file_id(message)
      document = message["document"]
      return document["file_id"] if document&.fetch("mime_type", "")&.start_with?("image/")

      message.fetch("photo", []).last&.fetch("file_id", nil)
    end

    def reply(text)
      @telegram.send_message(@config.telegram_chat_id, text)
    end

    def publish_notification(date)
      url = @config.absolute_url("posts/#{date.iso8601}.html")
      @telegram.send_message(@config.notification_chat_id, url)
      @store.mark_notification_published(date)
    end

    def publish_notification_if_ready(date)
      publish_notification(date) if @store.photo_on(date)
    end

    def schedule_notification(date)
      return if @store.notification_deferred?(date)
      return publish_notification(date) if @store.photo_on(date)

      @store.defer_notification(date)
    end

    def late_notification_time?(time)
      minutes_since_midnight(time) >= (LATE_NOTIFICATION_HOUR * 60) + LATE_NOTIFICATION_MINUTE
    end

    def minutes_since_midnight(time)
      (time.hour * 60) + time.min
    end
  end
end
