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
end
