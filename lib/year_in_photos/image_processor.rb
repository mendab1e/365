# frozen_string_literal: true

require "fileutils"
require "open3"
require "securerandom"

module YearInPhotos
  class ImageProcessor
    DESKTOP_SIZE = "2000x2000"
    QUALITY = "80"
    JPEG_SIGNATURE = "\xFF\xD8\xFF".b
    RESOURCE_LIMITS = %w[
      -limit width 20KP
      -limit height 20KP
      -limit area 100MP
      -limit memory 256MiB
      -limit map 512MiB
      -limit disk 1GiB
      -limit file 64
      -limit thread 2
      -limit time 120
      -limit list-length 2
    ].freeze

    def initialize(config:, command_runner: Open3.method(:capture3))
      @config = config
      @command_runner = command_runner
    end

    def process(source_path, date)
      validate_jpeg!(source_path)
      destinations = destination_paths(date)
      token = "#{Process.pid}-#{SecureRandom.hex(4)}"
      staging = destinations.map { |path| staging_path(path, "uploading", token) }
      create_variants(source_path, staging)
      photo = photo_metadata(date, destinations, dimensions(staging.first))
      replacements = staging.zip(destinations)
      commit_replacement(replacements, token) { yield(photo) if block_given? }
      photo
    ensure
      FileUtils.rm_f(staging || [])
    end

    private

    def validate_jpeg!(source_path)
      signature = File.open(source_path, "rb") { |file| file.read(JPEG_SIGNATURE.bytesize) }
      return if signature == JPEG_SIGNATURE

      raise ArgumentError, "Only JPEG/JPG images are accepted"
    end

    def destination_paths(date)
      directory = @config.data_dir.join("images")
      [directory.join("#{date.iso8601}.jpg"), directory.join("#{date.iso8601}-mobile.jpg")]
    end

    def create_variants(source_path, staging)
      FileUtils.mkdir_p(staging.first.dirname)
      convert(source_path, staging.first, DESKTOP_SIZE)
      convert(source_path, staging.last, @config.mobile_image_size)
    end

    def photo_metadata(date, destinations, dimensions)
      {
        date: date.iso8601,
        image: "images/#{destinations.first.basename}",
        mobile_image: "images/#{destinations.last.basename}",
        width: dimensions.first,
        height: dimensions.last
      }
    end

    def commit_replacement(replacements, token)
      backups = {}
      installed = []
      committed = false

      begin
        backup_destinations(replacements, token, backups)
        replacements.each do |staging, destination|
          File.rename(staging, destination)
          installed << destination
        end
        yield
        committed = true
      ensure
        rollback_replacement(installed, backups) unless committed
        FileUtils.rm_f(backups.values) if committed
      end
    end

    def backup_destinations(replacements, token, backups)
      replacements.each do |replacement|
        destination = replacement.last
        next unless destination.exist?

        backup = staging_path(destination, "backup", token)
        File.rename(destination, backup)
        backups[destination] = backup
      end
    end

    def rollback_replacement(installed, backups)
      FileUtils.rm_f(installed)
      backups.each do |destination, backup|
        File.rename(backup, destination) if backup.exist?
      end
    end

    def staging_path(destination, purpose, token)
      basename = destination.basename(destination.extname)
      destination.dirname.join(".#{basename}.#{purpose}-#{token}#{destination.extname}")
    end

    def convert(source, destination, size)
      args = [
        *RESOURCE_LIMITS, "jpeg:#{source}[0]", "-auto-orient", "-strip",
        "-resize", "#{size}>", "-quality", QUALITY,
        "-interlace", "Plane", destination.to_s
      ]
      run_image_magick!("convert", *args)
    end

    def dimensions(path)
      output = run_image_magick!("identify", *RESOURCE_LIMITS, "-format", "%w %h", path.to_s)
      output.split.map { |value| Integer(value, 10) }
    end

    def run_image_magick!(operation, *)
      command = operation == "identify" ? %w[magick identify] : ["magick"]
      command = [operation] if @legacy_commands
      run!(*command, *)
    rescue Errno::ENOENT
      if @legacy_commands
        raise "ImageMagick is required, but the `#{operation}` command was not found on PATH " \
              "(the `magick` command was also unavailable)"
      end

      @legacy_commands = true
      retry
    end

    def run!(*)
      stdout, stderr, status = @command_runner.call(*)
      return stdout if status.success?

      raise "ImageMagick failed: #{stderr.strip}"
    end
  end
end
