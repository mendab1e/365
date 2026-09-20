# frozen_string_literal: true

require "spec_helper"

RSpec.describe YearInPhotos::TelegramClient do
  subject(:client) { described_class.new("token", http_factory:) }

  let(:http) { fake_http_class.new(response) }
  let(:http_factory) { ->(_host, _port) { http } }
  let(:fake_http_class) do
    Class.new do
      attr_accessor :open_timeout, :read_timeout, :use_ssl

      def initialize(response)
        @response = response
      end

      def request(_request)
        @response
      end
    end
  end
  let(:fake_response_class) do
    Class.new do
      attr_reader :body, :code

      def initialize(code:, body:, success:)
        @code = code
        @body = body
        @success = success
      end

      def is_a?(klass)
        return @success if klass == Net::HTTPSuccess

        super
      end
    end
  end

  describe "#updates" do
    context "when Telegram returns an API error" do
      let(:response) do
        fake_response_class.new(
          code: "429",
          body: JSON.generate(ok: false, description: "Too Many Requests"),
          success: false
        )
      end

      it "reports Telegram's description" do
        expect { client.updates }.to raise_error(
          RuntimeError,
          "Telegram getUpdates failed: Too Many Requests"
        )
      end
    end

    context "when Telegram returns a non-JSON gateway response" do
      let(:response) do
        fake_response_class.new(code: "502", body: "Bad Gateway", success: false)
      end

      it "reports the HTTP status instead of leaking a JSON parser failure" do
        expect { client.updates }.to raise_error(
          RuntimeError,
          "Telegram getUpdates failed: HTTP 502 returned invalid JSON"
        )
      end
    end
  end

  describe "#download" do
    let(:response) { fake_response_class.new(code: "404", body: "missing", success: false) }

    it "raises a status-specific error without writing the destination" do
      Tempfile.create("telegram-download") do |destination|
        expect { client.download("photos/missing.jpg", destination) }
          .to raise_error(RuntimeError, "Telegram download failed: HTTP 404")
        expect(destination.size).to be_zero
      end
    end
  end
end
