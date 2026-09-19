# frozen_string_literal: true

require "spec_helper"

RSpec.describe YearInPhotos::Bot do
  subject(:bot) do
    described_class.new(
      config:,
      store:,
      services: described_class::Services.new(
        generator: instance_double(YearInPhotos::SiteGenerator),
        processor: instance_double(YearInPhotos::ImageProcessor),
        telegram:
      ),
      clock: class_double(Time, now: current_time),
      logger: instance_double(Logger, info: nil, error: nil)
    )
  end

  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:config) { build_config(root:) }
  let(:store) { YearInPhotos::PhotoStore.new(config.data_dir) }
  let(:telegram) { instance_double(YearInPhotos::TelegramClient, send_message: true) }
  let(:current_time) { Time.new(2026, 9, 19, 21, 1, 0, "+02:00") }

  after { FileUtils.rm_rf(root) }

  describe "#check_reminder" do
    it "sends one reminder after the configured hour when today's photo is missing" do
      bot.check_reminder(current_time)
      bot.check_reminder(current_time)

      expect(telegram).to have_received(:send_message).once
      expect(store.reminded?(current_time.to_date)).to be(true)
    end

    context "when today's photo has already been published" do
      before do
        store.save_photo(
          date: current_time.to_date.iso8601,
          image: "images/today.jpg",
          mobile_image: "images/today-mobile.jpg"
        )
      end

      it "does not send a reminder" do
        bot.check_reminder(current_time)

        expect(telegram).not_to have_received(:send_message)
      end
    end

    context "when it is earlier than the reminder hour" do
      let(:current_time) { Time.new(2026, 9, 19, 20, 59, 0, "+02:00") }

      it "does not send a reminder" do
        bot.check_reminder(current_time)

        expect(telegram).not_to have_received(:send_message)
      end
    end
  end

  describe "#check_notification" do
    let(:config) { build_config(root:, notification_chat_id: "@photo_channel") }

    context "when today's photo is present by 22:00" do
      before { save_today }

      it "publishes the dated page URL once at 22:00" do
        notification_time = Time.new(2026, 9, 19, 22, 0, 0, "+02:00")

        bot.check_notification(notification_time)
        bot.check_notification(notification_time)

        expect(telegram).to have_received(:send_message).with(
          "@photo_channel",
          "https://photos.example.test/posts/2026-09-19.html"
        ).once
        expect(store.notification_published?(notification_time.to_date)).to be(true)
      end
    end

    context "when today's photo is missing at 22:00" do
      it "defers a later photo until 23:59" do
        date = current_time.to_date
        bot.check_notification(Time.new(2026, 9, 19, 22, 0, 0, "+02:00"))
        save_today
        bot.check_notification(Time.new(2026, 9, 19, 23, 58, 30, "+02:00"))

        expect(telegram).not_to have_received(:send_message)

        bot.check_notification(Time.new(2026, 9, 19, 23, 59, 0, "+02:00"))

        expect(telegram).to have_received(:send_message).with(
          "@photo_channel",
          "https://photos.example.test/posts/2026-09-19.html"
        ).once
        expect(store.notification_deferred?(date)).to be(true)
        expect(store.notification_published?(date)).to be(true)
      end

      it "does not publish a nonexistent dated page at 23:59" do
        bot.check_notification(Time.new(2026, 9, 19, 22, 0, 0, "+02:00"))
        bot.check_notification(Time.new(2026, 9, 19, 23, 59, 0, "+02:00"))

        expect(telegram).not_to have_received(:send_message)
      end
    end

    context "when it is earlier than 22:00" do
      before { save_today }

      it "does not publish the URL" do
        bot.check_notification(Time.new(2026, 9, 19, 21, 59, 59, "+02:00"))

        expect(telegram).not_to have_received(:send_message)
      end
    end
  end

  def save_today
    store.save_photo(
      date: current_time.to_date.iso8601,
      image: "images/today.jpg",
      mobile_image: "images/today-mobile.jpg"
    )
  end
end
