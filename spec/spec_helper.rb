# frozen_string_literal: true

require "fileutils"
require "pathname"
require "tmpdir"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "year_in_photos"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand(config.seed)
end

def build_config(root:, **overrides)
  defaults = {
    telegram_token: "token",
    telegram_chat_id: "42",
    telegram_user_id: "7",
    notification_chat_id: nil,
    telegram_channel_url: nil,
    project_title: "365 Days",
    timezone: "Europe/Berlin",
    reminder_hour: 21,
    site_url: "https://photos.example.test",
    site_dir: root.join("public"),
    data_dir: root.join("data"),
    mobile_image_size: "900x1800"
  }
  YearInPhotos::Config.new(**defaults, **overrides)
end
