# frozen_string_literal: true

require "spec_helper"

RSpec.describe YearInPhotos::SitePublisher do
  describe ".new" do
    it "rejects a site directory that contains persistent data" do
      root = Pathname.new(Dir.mktmpdir)

      expect do
        described_class.new(site_dir: root, data_dir: root.join("data"))
      end.to raise_error(ArgumentError, "SITE_DIR cannot contain DATA_DIR")
    ensure
      FileUtils.rm_rf(root)
    end
  end
end
