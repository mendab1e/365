# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module YearInPhotos
  class TelegramClient
    API_ROOT = "https://api.telegram.org"

    def initialize(token, http_factory: Net::HTTP.method(:new))
      @token = token
      @http_factory = http_factory
    end

    def updates(offset: nil, timeout: 50)
      params = { timeout:, allowed_updates: JSON.generate(["message"]) }
      params[:offset] = offset if offset
      request("getUpdates", params, read_timeout: timeout + 10)
    end

    def send_message(chat_id, text)
      request("sendMessage", { chat_id:, text: })
    end

    def file_path(file_id)
      request("getFile", { file_id: }).fetch("file_path")
    end

    def download(file_path, destination)
      uri = URI("#{API_ROOT}/file/bot#{@token}/#{file_path}")
      response = http_for(uri).request(Net::HTTP::Get.new(uri))
      unless response.is_a?(Net::HTTPSuccess)
        raise "Telegram download failed: HTTP #{response.code}"
      end

      destination.binmode
      destination.write(response.body)
      destination.flush
      destination.rewind
    end

    private

    def request(method, params, read_timeout: 30)
      uri = URI("#{API_ROOT}/bot#{@token}/#{method}")
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(params)
      response = http_for(uri, read_timeout:).request(request)
      payload = parse_payload(response, method)
      return payload.fetch("result") if response.is_a?(Net::HTTPSuccess) && payload["ok"]

      description = payload.fetch("description", "HTTP #{response.code}")
      raise "Telegram #{method} failed: #{description}"
    end

    def parse_payload(response, method)
      JSON.parse(response.body)
    rescue JSON::ParserError
      raise "Telegram #{method} failed: HTTP #{response.code} returned invalid JSON"
    end

    def http_for(uri, read_timeout: 30)
      @http_factory.call(uri.host, uri.port).tap do |http|
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = read_timeout
      end
    end
  end
end
