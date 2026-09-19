# frozen_string_literal: true

require "spec_helper"

RSpec.describe YearInPhotos::Config do
  describe ".from_env" do
    let(:root) { Pathname.new(Dir.mktmpdir) }
    let(:environment_keys) do
      %w[
        PROJECT_ROOT PROJECT_TIMEZONE SITE_URL TELEGRAM_CHANNEL_URL TZ
        TELEGRAM_NOTIFICATION_CHAT_ID
      ]
    end
    let(:original_environment) { ENV.to_h.slice(*environment_keys) }

    before do
      environment_keys.each { |key| ENV.delete(key) }
      ENV["PROJECT_ROOT"] = root.to_s
      ENV["PROJECT_TIMEZONE"] = "Europe/Berlin"
      ENV["SITE_URL"] = "https://photos.example.test"
    end

    after do
      environment_keys.each { |key| ENV.delete(key) }
      original_environment.each { |key, value| ENV[key] = value }
      FileUtils.rm_rf(root)
    end

    it "derives a public Telegram URL from a channel username" do
      ENV["TELEGRAM_NOTIFICATION_CHAT_ID"] = "@photo_channel"

      config = described_class.from_env(require_telegram: false)

      expect(config.notification_chat_id).to eq("@photo_channel")
      expect(config.telegram_channel_url).to eq("https://t.me/photo_channel")
    end

    it "uses an explicit Telegram channel URL for numeric destinations" do
      ENV["TELEGRAM_NOTIFICATION_CHAT_ID"] = "-100123456789"
      ENV["TELEGRAM_CHANNEL_URL"] = "https://t.me/+invite-code/"

      config = described_class.from_env(require_telegram: false)

      expect(config.telegram_channel_url).to eq("https://t.me/+invite-code")
    end
  end
end
