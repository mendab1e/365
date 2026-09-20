# frozen_string_literal: true

require "fileutils"
require "pathname"
require "securerandom"
require "tmpdir"

module YearInPhotos
  class SitePublisher
    def initialize(site_dir:, data_dir:)
      @site_dir = site_dir.expand_path
      @data_dir = data_dir
      raise ArgumentError, "SITE_DIR cannot be a filesystem root" if @site_dir.root?
    end

    def publish
      with_lock do
        staging = create_staging_directory
        begin
          yield staging
          replace_site(staging)
        ensure
          FileUtils.rm_rf(staging) if staging.exist?
        end
      end
    end

    private

    def with_lock
      FileUtils.mkdir_p(@data_dir)
      lock_path = @data_dir.join(".site-generation.lock")
      File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      end
    end

    def create_staging_directory
      FileUtils.mkdir_p(@site_dir.dirname)
      staging = Pathname.new(
        Dir.mktmpdir(".#{@site_dir.basename}.generating-", @site_dir.dirname)
      )
      File.chmod(0o755, staging)
      staging
    end

    def replace_site(staging)
      backup = backup_path
      previous_site = @site_dir.exist? || @site_dir.symlink?
      File.rename(@site_dir, backup) if previous_site
      File.rename(staging, @site_dir)
      FileUtils.rm_rf(backup) if previous_site
    rescue StandardError
      restore_site(backup, previous_site)
      raise
    end

    def restore_site(backup, previous_site)
      return unless previous_site && backup.exist? && !@site_dir.exist?

      File.rename(backup, @site_dir)
    end

    def backup_path
      @site_dir.dirname.join(
        ".#{@site_dir.basename}.replaced-#{Process.pid}-#{SecureRandom.hex(4)}"
      )
    end
  end
end
