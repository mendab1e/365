# frozen_string_literal: true

require "fileutils"
require "open3"

module YearInPhotos
  class ImageProcessor
    DESKTOP_SIZE = "2000x2000"
    QUALITY = "80"

    def initialize(config:, command_runner: Open3.method(:capture3))
      @config = config
      @command_runner = command_runner
    end

    def process(source_path, date)
      desktop = @config.data_dir.join("images", "#{date.iso8601}.jpg")
      mobile = @config.data_dir.join("images", "#{date.iso8601}-mobile.jpg")
      desktop_staging = desktop.sub_ext(".uploading.jpg")
      mobile_staging = mobile.sub_ext(".uploading.jpg")
      FileUtils.mkdir_p(desktop.dirname)

      convert(source_path, desktop_staging, DESKTOP_SIZE)
      convert(source_path, mobile_staging, @config.mobile_image_size)
      width, height = dimensions(desktop_staging)
      File.rename(desktop_staging, desktop)
      File.rename(mobile_staging, mobile)

      {
        date: date.iso8601,
        image: "images/#{desktop.basename}",
        mobile_image: "images/#{mobile.basename}",
        width:,
        height:
      }
    rescue StandardError
      FileUtils.rm_f([desktop_staging, mobile_staging])
      raise
    end

    private

    def convert(source, destination, size)
      temporary = destination.sub_ext(".tmp.jpg")
      args = [
        "magick", "#{source}[0]", "-auto-orient", "-strip",
        "-resize", "#{size}>", "-quality", QUALITY,
        "-interlace", "Plane", temporary.to_s
      ]
      run!(*args)
      File.rename(temporary, destination)
    ensure
      FileUtils.rm_f(temporary) if temporary
    end

    def dimensions(path)
      output = run!("magick", "identify", "-format", "%w %h", path.to_s)
      output.split.map { |value| Integer(value, 10) }
    end

    def run!(*)
      stdout, stderr, status = @command_runner.call(*)
      return stdout if status.success?

      raise "ImageMagick failed: #{stderr.strip}"
    rescue Errno::ENOENT
      raise "ImageMagick is required, but the `magick` command was not found"
    end
  end
end
