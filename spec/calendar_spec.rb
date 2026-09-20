# frozen_string_literal: true

require "spec_helper"

RSpec.describe YearInPhotos::Calendar do
  subject(:calendar) do
    described_class.new(start_date: Date.new(2026, 9, 19), photo_dates: [photo_date])
  end

  let(:photo_date) { Date.new(2026, 9, 19) }

  describe "#months" do
    it "builds twelve consecutive months starting with the first upload month" do
      expect(calendar.months.map { |month| month.date.strftime("%Y-%m") })
        .to eq(%w[
                 2026-09 2026-10 2026-11 2026-12 2027-01 2027-02
                 2027-03 2027-04 2027-05 2027-06 2027-07 2027-08
               ])
    end

    it "marks only uploaded dates as having a photo" do
      days = calendar.months.flat_map { |month| month.weeks.flatten }
      uploaded = days.select(&:photo?).map(&:date)

      expect(uploaded).to eq([photo_date])
    end

    it "folds a photo from the same month next year into a colored-year layer" do
      next_year = Date.new(2027, 9, 17)
      folded = described_class.new(
        start_date: Date.new(2026, 9, 19),
        photo_dates: [photo_date, next_year]
      )
      september = folded.months.first
      day = september.weeks.flatten.find { |candidate| candidate.date.day == 17 }

      expect(september.later_years).to eq([2027])
      expect(day.photo_date).to eq(next_year)
      expect(day).to be_later_year
    end

    it "uses the latest year when the same month and day has multiple photos" do
      old_date = Date.new(2026, 9, 17)
      new_date = Date.new(2027, 9, 17)
      folded = described_class.new(start_date: old_date, photo_dates: [old_date, new_date])
      day = folded.months.first.weeks.flatten.find { |candidate| candidate.date.day == 17 }

      expect(day.photo_date).to eq(new_date)
    end

    it "includes a leap day from a later folded year" do
      leap_day = Date.new(2028, 2, 29)
      folded = described_class.new(start_date: Date.new(2026, 2, 1), photo_dates: [leap_day])
      february = folded.months.first
      day = february.weeks.flatten.find do |candidate|
        candidate.in_month && candidate.date.day == 29
      end

      expect(february.later_years).to eq([2028])
      expect(day.photo_date).to eq(leap_day)
      expect(day).to be_later_year
    end

    it "memoizes its immutable month grid" do
      expect(calendar.months).to equal(calendar.months)
    end
  end
end
