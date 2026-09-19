# frozen_string_literal: true

require "date"

module YearInPhotos
  class Calendar
    Month = Data.define(:date, :weeks, :later_years)
    Day = Data.define(:date, :in_month, :photo_date) do
      def photo?
        !photo_date.nil?
      end

      def later_year?
        photo? && photo_date.year > date.year
      end
    end

    attr_reader :start_month

    def initialize(start_date:, photo_dates:)
      @start_month = Date.new(start_date.year, start_date.month, 1)
      @photo_dates = photo_dates.sort
    end

    def months
      12.times.map { |offset| build_month(start_month >> offset) }
    end

    private

    def build_month(month)
      grid_start = month - (month.cwday - 1)
      grid_end = (month.next_month - 1) + (7 - (month.next_month - 1).cwday)
      days = (grid_start..grid_end).map do |date|
        in_month = date.month == month.month
        photo_date = latest_photo_for(date) if in_month
        Day.new(date:, in_month:, photo_date:)
      end
      Month.new(
        date: month,
        weeks: days.each_slice(7).to_a,
        later_years: later_years_for(month)
      )
    end

    def latest_photo_for(date)
      @photo_dates.reverse.find do |photo_date|
        photo_date.year >= date.year && photo_date.month == date.month && photo_date.day == date.day
      end
    end

    def later_years_for(month)
      @photo_dates
        .select { |date| date.month == month.month && date.year > month.year }
        .map(&:year)
        .uniq
    end
  end
end
