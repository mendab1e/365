# frozen_string_literal: true

require "date"

module YearInPhotos
  class Calendar
    Month = Data.define(:date, :weeks, :later_years)
    Day = Data.define(:date, :in_month, :photo_date, :calendar_year) do
      def photo?
        !photo_date.nil?
      end

      def later_year?
        photo? && photo_date.year > calendar_year
      end
    end

    attr_reader :start_month

    def initialize(start_date:, photo_dates:)
      @start_month = Date.new(start_date.year, start_date.month, 1)
      @photo_dates = photo_dates.sort
      @latest_photos = @photo_dates.group_by { |date| [date.month, date.day] }
                                   .transform_values(&:max)
      @years_by_month = @photo_dates.group_by(&:month)
                                    .transform_values { |dates| dates.map(&:year).uniq.sort }
    end

    def months
      @months ||= 12.times.map { |offset| build_month(start_month >> offset) }.freeze
    end

    private

    def build_month(month)
      days = leading_days(month)
      days.concat(month_days(month))
      days.concat(trailing_days(month, days.length))
      Month.new(
        date: month,
        weeks: days.each_slice(7).to_a,
        later_years: later_years_for(month)
      )
    end

    def leading_days(month)
      grid_start = month - (month.cwday - 1)
      (grid_start...month).map do |date|
        Day.new(date:, in_month: false, photo_date: nil, calendar_year: month.year)
      end
    end

    def month_days(month)
      (1..last_display_day(month)).map do |day|
        photo_date = latest_photo_for(month, day)
        date = day <= last_calendar_day(month) ? Date.new(month.year, month.month, day) : photo_date
        Day.new(date:, in_month: true, photo_date:, calendar_year: month.year)
      end
    end

    def trailing_days(month, current_length)
      count = (7 - (current_length % 7)) % 7
      count.times.map do |offset|
        Day.new(
          date: month.next_month + offset,
          in_month: false,
          photo_date: nil,
          calendar_year: month.year
        )
      end
    end

    def last_display_day(month)
      later_photo_days = @photo_dates.filter_map do |date|
        date.day if date.month == month.month && date.year >= month.year
      end
      [last_calendar_day(month), *later_photo_days].max
    end

    def last_calendar_day(month)
      (month.next_month - 1).day
    end

    def latest_photo_for(month, day)
      photo_date = @latest_photos[[month.month, day]]
      photo_date if photo_date && photo_date.year >= month.year
    end

    def later_years_for(month)
      @years_by_month.fetch(month.month, []).select { |year| year > month.year }
    end
  end
end
