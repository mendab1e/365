# frozen_string_literal: true

require "spec_helper"

RSpec.describe YearInPhotos::Bot do
  subject(:bot) do
    described_class.new(
      config:,
      store:,
      services: described_class::Services.new(
        generator:,
        processor:,
        telegram:
      ),
      clock:,
      logger: instance_double(Logger, info: nil, error: nil)
    )
  end

  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:config) { build_config(root:) }
  let(:store) { YearInPhotos::PhotoStore.new(config.data_dir) }
  let(:generator) { instance_double(YearInPhotos::SiteGenerator, generate!: true) }
  let(:processor) { instance_double(YearInPhotos::ImageProcessor) }
  let(:telegram) { instance_double(YearInPhotos::TelegramClient, send_message: true) }
  let(:clock) { class_double(Time, now: current_time) }
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

  describe "#handle_update" do
    let(:sent_time) { Time.new(2026, 9, 19, 23, 59, 59, "+02:00") }
    let(:current_time) { Time.new(2026, 9, 20, 0, 0, 1, "+02:00") }
    let(:timestamp) { sent_time.to_i }
    let(:photo) do
      {
        date: sent_time.to_date.iso8601,
        image: "images/2026-09-19.jpg",
        mobile_image: "images/2026-09-19-mobile.jpg",
        width: 1500,
        height: 2000
      }
    end
    let(:update) do
      {
        "message" => {
          "date" => timestamp,
          "chat" => { "id" => 42 },
          "from" => { "id" => 7 },
          "photo" => [{ "file_id" => "small" }, { "file_id" => "large" }]
        }
      }
    end

    before do
      allow(clock).to receive(:at).with(timestamp).and_return(sent_time)
      allow(telegram).to receive(:file_path).with("large").and_return("photos/upload.jpg")
      allow(telegram).to receive(:download) do |_path, destination|
        destination.write("source")
        destination.rewind
      end
      allow(processor).to receive(:process) do |_path, date, &publication|
        expect(date).to eq(sent_time.to_date)
        publication.call(photo)
        photo
      end
    end

    it "uses the Telegram message timestamp when processing crosses midnight" do
      bot.handle_update(update)

      expect(store.photo_on(sent_time.to_date)).to eq(photo)
      expect(store.photo_on(current_time.to_date)).to be_nil
      expect(telegram).to have_received(:send_message).with("42", /September 19, 2026/)
    end

    it "restores the previous metadata when site generation fails" do
      previous = photo.merge(width: 1000, height: 1000)
      store.save_photo(previous)
      allow(generator).to receive(:generate!).and_raise("template failure")

      bot.handle_update(update)

      expect(store.photo_on(sent_time.to_date)).to eq(previous)
      expect(telegram).to have_received(:send_message).with("42", /template failure/)
    end

    it "ignores messages from a different chat" do
      update.fetch("message").fetch("chat")["id"] = 99

      bot.handle_update(update)

      expect(processor).not_to have_received(:process)
      expect(telegram).not_to have_received(:send_message)
    end

    it "ignores messages from a different user" do
      update.fetch("message").fetch("from")["id"] = 8

      bot.handle_update(update)

      expect(processor).not_to have_received(:process)
      expect(telegram).not_to have_received(:send_message)
    end

    it "accepts JPEG image documents" do
      message = update.fetch("message")
      message.delete("photo")
      message["document"] = { "file_id" => "large", "mime_type" => "image/jpeg" }

      bot.handle_update(update)

      expect(processor).to have_received(:process)
    end

    it "accepts the image/jpg alias for JPEG image documents" do
      message = update.fetch("message")
      message.delete("photo")
      message["document"] = { "file_id" => "large", "mime_type" => "image/jpg" }

      bot.handle_update(update)

      expect(processor).to have_received(:process)
    end

    it "rejects non-JPEG image documents" do
      message = update.fetch("message")
      message.delete("photo")
      message["document"] = { "file_id" => "large", "mime_type" => "image/png" }

      bot.handle_update(update)

      expect(processor).not_to have_received(:process)
      expect(telegram).to have_received(:send_message).with(
        "42",
        "Only JPEG/JPG image documents are accepted."
      )
    end

    it "dispatches a group command addressed to the bot" do
      command_update = {
        "message" => {
          "date" => timestamp,
          "chat" => { "id" => 42 },
          "from" => { "id" => 7 },
          "text" => "/status@photo_bot"
        }
      }

      bot.handle_update(command_update)

      expect(telegram).to have_received(:send_message).with("42", /still missing/)
    end

    it "waits for an in-progress upload before deciding to send a reminder" do
      processing = Queue.new
      release_upload = Queue.new
      allow(processor).to receive(:process) do |_path, _date, &publication|
        processing << true
        release_upload.pop
        publication.call(photo)
      end

      upload_thread = Thread.new { bot.handle_update(update) }
      processing.pop
      reminder_thread = Thread.new { bot.check_reminder(sent_time) }

      expect(reminder_thread.join(0.05)).to be_nil
      release_upload << true
      upload_thread.join
      reminder_thread.join

      expect(telegram).not_to have_received(:send_message).with("42", /still missing/)
    ensure
      release_upload << true if upload_thread&.alive?
      upload_thread&.join
      reminder_thread&.join
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
