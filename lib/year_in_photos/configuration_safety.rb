# frozen_string_literal: true

module YearInPhotos
  module ConfigurationSafety
    module_function

    def validate_telegram!(token:, chat_id:, user_id:)
      raise ArgumentError, "TELEGRAM_BOT_TOKEN is required" if token.to_s.strip.empty?
      raise ArgumentError, "TELEGRAM_CHAT_ID is required" if chat_id.to_s.strip.empty?
      raise ArgumentError, "TELEGRAM_USER_ID is required" if user_id.to_s.strip.empty?
    end

    def validate_site_dir!(site_dir:, data_dir:, project_root: nil)
      output = site_dir.expand_path
      raise ArgumentError, "SITE_DIR cannot be a filesystem root" if output.root?

      protected_paths = [["PROJECT_ROOT", project_root], ["DATA_DIR", data_dir]]
      protected_name = protected_paths.find do |_name, path|
        path && contained_by?(path.expand_path, output)
      end&.first
      raise ArgumentError, "SITE_DIR cannot contain #{protected_name}" if protected_name
    end

    def contained_by?(path, directory)
      path == directory || path.to_s.start_with?("#{directory}#{File::SEPARATOR}")
    end
    private_class_method :contained_by?
  end
end
