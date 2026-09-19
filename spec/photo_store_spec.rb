# frozen_string_literal: true

require "spec_helper"

RSpec.describe YearInPhotos::PhotoStore do
  subject(:store) { described_class.new(Pathname.new(directory)) }

  let(:directory) { Dir.mktmpdir }

  after { FileUtils.rm_rf(directory) }

  describe "#save_photo" do
    let(:original) do
      { date: "2026-09-19", image: "images/original.jpg", mobile_image: "images/mobile.jpg" }
    end
    let(:replacement) do
      { date: "2026-09-19", image: "images/replacement.jpg", mobile_image: "images/mobile.jpg" }
    end

    it "replaces an existing photo for the same date" do
      store.save_photo(original)
      store.save_photo(replacement)

      expect(store.photos).to contain_exactly(replacement)
    end
  end

  describe "reminders" do
    let(:date) { Date.new(2026, 9, 19) }

    it "persists that a reminder was sent" do
      expect { store.mark_reminded(date) }
        .to change { store.reminded?(date) }.from(false).to(true)
    end
  end
end
