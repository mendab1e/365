# frozen_string_literal: true

require "cgi"
require "date"
require "erb"
require "fileutils"
require "rss"
require "time"

module YearInPhotos
  class SiteGenerator
    TEMPLATE_DIR = Pathname.new(__dir__).join("../../templates").expand_path
    AI_CRAWLERS = %w[
      AI2Bot Amazonbot Applebot-Extended Bytespider CCBot ChatGPT-User ClaudeBot
      Claude-SearchBot Claude-User Diffbot GPTBot Google-Extended ImagesiftBot
      Meta-ExternalAgent OAI-SearchBot PerplexityBot Perplexity-User Timpibot
      YouBot anthropic-ai cohere-ai meta-externalfetcher omgili omgilibot
    ].freeze

    def initialize(config:, store:, now: -> { Time.now })
      @config = config
      @store = store
      @now = now
    end

    def generate!
      @photos = nil
      @calendar = nil
      publisher.publish do |output_dir|
        @output_dir = output_dir
        begin
          generate_site_files
        ensure
          @output_dir = nil
        end
      end
    end

    private

    def generate_site_files
      FileUtils.mkdir_p(@output_dir.join("posts"))
      copy_assets
      copy_images
      render_index
      render_about
      render_posts
      render_feed
      write("sitemap.xml", render_template("sitemap.xml.erb"))
      write("robots.txt", render_template("robots.txt.erb"))
    end

    def publisher
      @publisher ||= SitePublisher.new(site_dir: @config.site_dir, data_dir: @config.data_dir)
    end

    def render_index
      render_page(
        "index",
        title: @config.project_title,
        description: "A daily photo project.",
        path: "",
        social_photo: photos.first
      )
    end

    def render_about
      render_page(
        "about",
        title: "About — #{@config.project_title}",
        description: "About #{@config.project_title}.",
        path: "about.html",
        social_photo: photos.first
      )
    end

    def render_posts
      photos.each do |photo|
        @photo = photo
        render_page(
          "post",
          title: "#{long_date(photo)} — #{@config.project_title}",
          description: "Photo for #{long_date(photo)}.",
          path: "posts/#{photo.fetch(:date)}.html",
          social_photo: photo,
          type: "article"
        )
      end
    end

    def render_page(template, path:, **metadata)
      prepare_page(path:, **metadata)
      @content = render(template)
      write(path.empty? ? "index.html" : path, render("layout"))
    end

    def prepare_page(title:, description:, path:, social_photo:, type: "website")
      @page_title = title
      @description = description
      @canonical_url = absolute(path)
      @social_photo = social_photo
      @social_image_url = absolute(social_photo.fetch(:image)) if social_photo
      @social_image_alt = "Photo for #{long_date(social_photo)}" if social_photo
      @page_type = type
    end

    def render_feed
      feed = RSS::Maker.make("2.0") do |maker|
        maker.channel.title = @config.project_title
        maker.channel.link = @config.site_url
        maker.channel.description = "A daily photo project."
        maker.channel.updated = @now.call

        photos.reverse_each { |photo| add_feed_item(maker, photo) }
      end
      write("feed.xml", feed.to_s)
    end

    def add_feed_item(maker, photo)
      data = feed_item_data(photo)
      maker.items.new_item do |item|
        item.title = data.fetch(:title)
        item.link = data.fetch(:link)
        item.guid.content = data.fetch(:link)
        item.guid.isPermaLink = true
        item.updated = data.fetch(:updated)
        item.description = data.fetch(:description)
      end
    end

    def feed_item_data(photo)
      date = Date.iso8601(photo.fetch(:date))
      title = long_date(photo)
      {
        title:,
        link: absolute("posts/#{photo.fetch(:date)}.html"),
        updated: Time.local(date.year, date.month, date.day, 12),
        description: %(<p><img src="#{absolute(photo.fetch(:image))}" ) +
          %(alt="Photo for #{title}"></p>\n)
      }
    end

    def copy_assets
      FileUtils.cp_r(TEMPLATE_DIR.join("assets"), @output_dir.join("assets"))
    end

    def copy_images
      photos.flat_map { |photo| photo.values_at(:image, :mobile_image) }.uniq.each do |path|
        destination = @output_dir.join(path)
        FileUtils.mkdir_p(destination.dirname)
        FileUtils.cp(@config.data_dir.join(path), destination)
      end
    end

    def photos
      @photos ||= @store.photos
    end

    def calendar
      return @calendar if @calendar

      dates = photos.map { |photo| Date.iso8601(photo.fetch(:date)) }
      @calendar = Calendar.new(start_date: dates.first || @now.call.to_date, photo_dates: dates)
    end

    def long_date(photo)
      Date.iso8601(photo.fetch(:date)).strftime("%A, %B %-d, %Y")
    end

    def render(name, **locals)
      render_template("#{name}.html.erb", **locals)
    end

    def render_template(filename, **locals)
      context = binding
      locals.each { |name, value| context.local_variable_set(name, value) }
      ERB.new(TEMPLATE_DIR.join(filename).read, trim_mode: "-").result(context)
    end

    def write(relative_path, contents)
      destination = @output_dir.join(relative_path)
      FileUtils.mkdir_p(destination.dirname)
      destination.write(contents)
    end

    def public_path(path)
      @config.public_path(path)
    end

    def absolute(path)
      @config.absolute_url(path)
    end

    def h(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
