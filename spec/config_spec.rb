# frozen_string_literal: true

require "spec_helper"

RSpec.describe YearInPhotos::Config do
  describe ".from_env" do
    let(:root) { Pathname.new(Dir.mktmpdir) }
    let(:environment_keys) do
      %w[
        DATA_DIR PROJECT_ROOT PROJECT_TIMEZONE SITE_DIR SITE_URL TELEGRAM_BOT_TOKEN
        TELEGRAM_CHANNEL_URL TELEGRAM_CHAT_ID TELEGRAM_NOTIFICATION_CHAT_ID TELEGRAM_USER_ID TZ
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

    it "rejects site URLs with a query string" do
      ENV["SITE_URL"] = "https://photos.example.test/project?preview=1"

      expect { described_class.from_env(require_telegram: false) }
        .to raise_error(ArgumentError, /without a query string or fragment/)
    end

    it "rejects site URLs with a fragment" do
      ENV["SITE_URL"] = "https://photos.example.test/project#preview"

      expect { described_class.from_env(require_telegram: false) }
        .to raise_error(ArgumentError, /without a query string or fragment/)
    end

    it "requires a Telegram user ID when starting the bot" do
      ENV["TELEGRAM_BOT_TOKEN"] = "token"
      ENV["TELEGRAM_CHAT_ID"] = "42"

      expect { described_class.from_env }
        .to raise_error(ArgumentError, "TELEGRAM_USER_ID is required")
    end

    it "rejects the project root as the generated site directory" do
      ENV["SITE_DIR"] = "."

      expect { described_class.from_env(require_telegram: false) }
        .to raise_error(ArgumentError, "SITE_DIR cannot contain PROJECT_ROOT")
    end

    it "rejects a generated site directory that contains the data directory" do
      ENV["SITE_DIR"] = "output"
      ENV["DATA_DIR"] = "output/data"

      expect { described_class.from_env(require_telegram: false) }
        .to raise_error(ArgumentError, "SITE_DIR cannot contain DATA_DIR")
    end
  end

  describe "#absolute_url" do
    it "constructs URLs below the configured site path" do
      config = build_config(
        root: Pathname.new(Dir.mktmpdir),
        site_url: "https://photos.example.test/project"
      )

      expect(config.absolute_url("posts/2026-09-19.html"))
        .to eq("https://photos.example.test/project/posts/2026-09-19.html")
    ensure
      FileUtils.rm_rf(config&.site_dir&.dirname)
    end
  end
end
