# frozen_string_literal: true

require "spec_helper"

RSpec.describe YearInPhotos::ImageProcessor do
  subject(:processor) { described_class.new(config:, command_runner:) }

  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:config) { build_config(root:) }
  let(:source) { root.join("incoming.jpg") }
  let(:commands) { [] }
  let(:success) { instance_double(Process::Status, success?: true) }
  let(:missing_commands) { [] }
  let(:command_runner) do
    lambda do |*arguments|
      commands << arguments
      raise Errno::ENOENT, arguments.first if missing_commands.include?(arguments.first)

      if arguments[1] == "identify" || arguments.first == "identify"
        ["1500 2000", "", success]
      else
        FileUtils.mkdir_p(Pathname.new(arguments.last).dirname)
        File.write(arguments.last, "processed")
        ["", "", success]
      end
    end
  end

  before { source.binwrite("\xFF\xD8\xFFsource".b) }
  after { FileUtils.rm_rf(root) }

  describe "#process" do
    context "when magick is unavailable" do
      let(:missing_commands) { ["magick"] }

      it "uses convert and identify with the same resource limits and preserves the source" do
        original = source.binread
        result = processor.process(source, Date.new(2026, 9, 19))

        expect(commands.map(&:first)).to eq(%w[magick convert convert identify])
        commands.drop(1).each do |command|
          expect(command[1, described_class::RESOURCE_LIMITS.length])
            .to eq(described_class::RESOURCE_LIMITS)
        end
        expect(result).to include(width: 1500, height: 2000)
        expect(source.binread).to eq(original)
      end
    end

    context "when neither magick nor convert is available" do
      let(:missing_commands) { %w[magick convert] }

      it "names the missing fallback command" do
        expect { processor.process(source, Date.new(2026, 9, 19)) }
          .to raise_error(RuntimeError, /`convert` command was not found on PATH/)
      end
    end

    context "when the fallback identify command is unavailable" do
      let(:missing_commands) { %w[magick identify] }

      it "reports the missing command and cleans staged conversions" do
        expect { processor.process(source, Date.new(2026, 9, 19)) }
          .to raise_error(RuntimeError, /`identify` command was not found on PATH/)
        expect(config.data_dir.join("images").children).to be_empty
      end
    end

    it "creates desktop and mobile images with aspect-preserving bounds and quality 80" do
      result = processor.process(source, Date.new(2026, 9, 19))
      conversions = commands.reject { |command| command[1] == "identify" }

      expect(conversions.map { |command| command[command.index("-resize") + 1] })
        .to eq(%w[2000x2000> 900x1800>])
      expect(conversions).to all(include("-auto-orient", "-strip", "-quality", "80"))
      expect(conversions).to all(include("-limit", "memory", "256MiB", "time", "120"))
      sources = conversions.map do |command|
        command.find { |argument| argument.start_with?("jpeg:") }
      end
      expect(sources).to all(end_with("[0]"))
      expect(result).to include(width: 1500, height: 2000)
    end

    it "rejects a non-JPEG file before invoking ImageMagick" do
      source.binwrite("not a jpeg")

      expect { processor.process(source, Date.new(2026, 9, 19)) }
        .to raise_error(ArgumentError, "Only JPEG/JPG images are accepted")
      expect(commands).to be_empty
    end

    it "cleans partial conversions while preserving existing images and the source" do
      date = Date.new(2026, 9, 19)
      processor.process(source, date)
      original = source.binread
      failed = instance_double(Process::Status, success?: false)
      failing_runner = lambda do |*arguments|
        expect(arguments.first).to eq("magick")
        File.write(arguments.last, "partial conversion")
        ["", "conversion failed", failed]
      end
      failing_processor = described_class.new(config:, command_runner: failing_runner)

      expect { failing_processor.process(source, date) }
        .to raise_error(/conversion failed/)

      images = config.data_dir.join("images").children
      expect(images.map { |path| path.basename.to_s })
        .to contain_exactly("2026-09-19.jpg", "2026-09-19-mobile.jpg")
      expect(images.map(&:read)).to eq(%w[processed processed])
      expect(source.binread).to eq(original)
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
