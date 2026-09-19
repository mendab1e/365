# frozen_string_literal: true

require "pathname"
require "uri"

module YearInPhotos
  Config = Data.define(
    :telegram_token,
    :telegram_chat_id,
    :telegram_user_id,
    :project_title,
    :timezone,
    :reminder_hour,
    :site_url,
    :site_dir,
    :data_dir,
    :mobile_image_size
  ) do
    def self.from_env(require_telegram: true)
      root = Pathname.new(ENV.fetch("PROJECT_ROOT", Dir.pwd)).expand_path
      token = ENV.fetch("TELEGRAM_BOT_TOKEN", nil)
      chat_id = ENV.fetch("TELEGRAM_CHAT_ID", nil)
      validate_telegram!(token, chat_id) if require_telegram

      timezone = ENV.fetch("PROJECT_TIMEZONE", "Europe/Berlin")
      ENV["TZ"] = timezone

      new(**environment_attributes(root, token, chat_id, timezone)).tap(&:validate!)
    end

    def self.environment_attributes(root, token, chat_id, timezone)
      {
        telegram_token: token,
        telegram_chat_id: chat_id&.to_s,
        telegram_user_id: ENV.fetch("TELEGRAM_USER_ID", nil)&.to_s,
        project_title: ENV.fetch("PROJECT_TITLE", "365 Days"),
        timezone:,
        reminder_hour: Integer(ENV.fetch("REMINDER_HOUR", "21"), 10),
        site_url: normalize_url(ENV.fetch("SITE_URL", "https://example.com")),
        site_dir: expand(root, ENV.fetch("SITE_DIR", "public")),
        data_dir: expand(root, ENV.fetch("DATA_DIR", "data")),
        mobile_image_size: ENV.fetch("MOBILE_IMAGE_SIZE", "1290x2796")
      }
    end

    def validate!
      raise ArgumentError, "REMINDER_HOUR must be from 0 to 23" unless (0..23).cover?(reminder_hour)
      raise ArgumentError, "SITE_URL must be an absolute HTTP(S) URL" unless absolute_http_url?
      return if mobile_image_size.match?(/\A\d+x\d+\z/)

      raise ArgumentError, "MOBILE_IMAGE_SIZE must look like 1290x2796"
    end

    def base_path
      path = URI(site_url).path.sub(%r{/\z}, "")
      path == "/" ? "" : path
    end

    def public_path(path)
      "#{base_path}/#{path.sub(%r{\A/}, '')}".sub(%r{\A//}, "/")
    end

    def absolute_url(path)
      "#{site_url}/#{path.sub(%r{\A/}, '')}".sub(%r{(?<!:)//+}, "/")
    end

    class << self
      private

      def validate_telegram!(token, chat_id)
        raise ArgumentError, "TELEGRAM_BOT_TOKEN is required" if token.to_s.empty?
        raise ArgumentError, "TELEGRAM_CHAT_ID is required" if chat_id.to_s.empty?
      end

      def normalize_url(url)
        url.sub(%r{/+\z}, "")
      end

      def expand(root, value)
        path = Pathname.new(value)
        path.absolute? ? path : root.join(path)
      end
    end

    private

    def absolute_http_url?
      uri = URI(site_url)
      %w[http https].include?(uri.scheme) && uri.host
    rescue URI::InvalidURIError
      false
    end
  end
end
