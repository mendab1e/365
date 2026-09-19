# frozen_string_literal: true

require "spec_helper"

RSpec.describe YearInPhotos::ImageProcessor do
  subject(:processor) { described_class.new(config:, command_runner:) }

  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:config) { build_config(root:) }
  let(:source) { root.join("incoming.jpg") }
  let(:commands) { [] }
  let(:success) { instance_double(Process::Status, success?: true) }
  let(:command_runner) do
    lambda do |*arguments|
      commands << arguments
      if arguments[1] == "identify"
        ["1500 2000", "", success]
      else
        FileUtils.mkdir_p(Pathname.new(arguments.last).dirname)
        File.write(arguments.last, "processed")
        ["", "", success]
      end
    end
  end

  before { source.write("source") }
  after { FileUtils.rm_rf(root) }

  describe "#process" do
    it "creates desktop and mobile images with aspect-preserving bounds and quality 80" do
      result = processor.process(source, Date.new(2026, 9, 19))
      conversions = commands.reject { |command| command[1] == "identify" }

      expect(conversions.map { |command| command[command.index("-resize") + 1] })
        .to eq(%w[2000x2000> 1290x2796>])
      expect(conversions).to all(include("-auto-orient", "-strip", "-quality", "80"))
      expect(result).to include(width: 1500, height: 2000)
    end
  end
end
