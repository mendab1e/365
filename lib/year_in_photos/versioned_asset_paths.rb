# frozen_string_literal: true

require "digest"

module YearInPhotos
  module VersionedAssetPaths
    private

    def asset_path(filename)
      source = self.class::TEMPLATE_DIR.join("assets", filename)
      version = Digest::SHA256.file(source).hexdigest[0, 12]
      "#{public_path("assets/#{filename}")}?v=#{version}"
    end
  end
end
