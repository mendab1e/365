# frozen_string_literal: true

require "date"
require "fileutils"
require "json"

module YearInPhotos
  class PhotoStore
    attr_reader :data_dir, :images_dir

    def initialize(data_dir)
      @data_dir = data_dir
      @images_dir = data_dir.join("images")
      FileUtils.mkdir_p(images_dir)
    end

    def photos
      read_json(photos_path, [])
        .map { |photo| symbolize(photo) }
        .sort_by { |photo| photo.fetch(:date) }
    end

    def photo_on(date)
      photos.find { |photo| photo.fetch(:date) == date.iso8601 }
    end

    def save_photo(photo)
      collection = photos.reject { |item| item.fetch(:date) == photo.fetch(:date) }
      collection << photo
      write_json(photos_path, collection.sort_by { |item| item.fetch(:date) })
    end

    def first_date
      value = photos.first&.fetch(:date, nil)
      Date.iso8601(value) if value
    end

    def reminded?(date)
      read_json(reminders_path, []).include?(date.iso8601)
    end

    def mark_reminded(date)
      dates = read_json(reminders_path, []) | [date.iso8601]
      write_json(reminders_path, dates.sort)
    end

    private

    def photos_path
      data_dir.join("photos.json")
    end

    def reminders_path
      data_dir.join("reminders.json")
    end

    def read_json(path, fallback)
      return fallback unless path.exist?

      JSON.parse(path.read)
    rescue JSON::ParserError => e
      raise "Cannot parse #{path}: #{e.message}"
    end

    def write_json(path, value)
      FileUtils.mkdir_p(path.dirname)
      temporary = path.sub_ext("#{path.extname}.tmp")
      temporary.write("#{JSON.pretty_generate(value)}\n")
      File.rename(temporary, path)
    end

    def symbolize(hash)
      hash.transform_keys(&:to_sym)
    end
  end
end
