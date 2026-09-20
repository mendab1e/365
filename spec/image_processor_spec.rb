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
        .to eq(%w[2000x2000> 900x1800>])
      expect(conversions).to all(include("-auto-orient", "-strip", "-quality", "80"))
      expect(result).to include(width: 1500, height: 2000)
    end

    it "restores both previous variants when publication fails" do
      desktop = config.data_dir.join("images/2026-09-19.jpg")
      mobile = config.data_dir.join("images/2026-09-19-mobile.jpg")
      FileUtils.mkdir_p(desktop.dirname)
      desktop.write("old desktop")
      mobile.write("old mobile")

      expect do
        processor.process(source, Date.new(2026, 9, 19)) { raise "publication failed" }
      end.to raise_error("publication failed")

      expect(desktop.read).to eq("old desktop")
      expect(mobile.read).to eq("old mobile")
      expect(desktop.dirname.children.map(&:to_s).grep(/uploading|backup/)).to be_empty
    end

    it "restores both previous variants when the second install fails" do
      desktop = config.data_dir.join("images/2026-09-19.jpg")
      mobile = config.data_dir.join("images/2026-09-19-mobile.jpg")
      FileUtils.mkdir_p(desktop.dirname)
      desktop.write("old desktop")
      mobile.write("old mobile")
      rename = File.method(:rename)
      allow(File).to receive(:rename) do |source_path, destination_path|
        if source_path.to_s.match?(/mobile\.uploading-.*\.jpg\z/)
          raise SystemCallError, "simulated install failure"
        end

        rename.call(source_path, destination_path)
      end

      expect { processor.process(source, Date.new(2026, 9, 19)) }
        .to raise_error(SystemCallError, /simulated install failure/)

      expect(desktop.read).to eq("old desktop")
      expect(mobile.read).to eq("old mobile")
    end
  end
end
