# frozen_string_literal: true

require "spec_helper"

RSpec.describe YearInPhotos::SiteGenerator do
  subject(:generator) { described_class.new(config:, store:, now: -> { now }) }

  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:config) { build_config(root:) }
  let(:store) { YearInPhotos::PhotoStore.new(config.data_dir) }
  let(:now) { Time.new(2026, 9, 20, 12, 0, 0, "+02:00") }

  before do
    save_photo("2026-09-19")
    generator.generate!
  end

  after { FileUtils.rm_rf(root) }

  describe "#generate!" do
    it "creates the pages, feeds, and crawler discovery files" do
      expect(config.site_dir.join("index.html")).to exist
      expect(config.site_dir.join("about.html")).to exist
      expect(config.site_dir.join("feed.xml")).to exist
      expect(config.site_dir.join("sitemap.xml")).to exist
      expect(config.site_dir.join("robots.txt")).to exist
      expect(config.site_dir.join("posts/2026-09-19.html")).to exist
    end

    it "links uploaded dates while leaving missing dates as plain text" do
      index = config.site_dir.join("index.html").read

      expect(index).to include("posts/2026-09-19.html")
      expect(index).not_to include("posts/2026-09-20.html")
    end

    it "refreshes an old post calendar after a later upload" do
      save_photo("2026-09-20")
      generator.generate!
      old_page = config.site_dir.join("posts/2026-09-19.html").read

      expect(old_page).to include("posts/2026-09-20.html")
    end

    it "removes pages and images that are no longer in the source data" do
      store.delete_photo(Date.new(2026, 9, 19))
      FileUtils.rm_f(store.images_dir.children)

      generator.generate!

      expect(config.site_dir.join("posts/2026-09-19.html")).not_to exist
      expect(config.site_dir.join("images/2026-09-19.jpg")).not_to exist
      expect(config.site_dir.join("images/2026-09-19-mobile.jpg")).not_to exist
    end

    it "keeps the previous complete site when generation fails" do
      original_index = config.site_dir.join("index.html").read
      allow(generator).to receive(:render_about).and_raise("template failure")

      expect { generator.generate! }.to raise_error("template failure")

      expect(config.site_dir.join("index.html").read).to eq(original_index)
      expect(config.site_dir.join("posts/2026-09-19.html")).to exist
    end

    it "uses the mobile image in a responsive picture source" do
      index = config.site_dir.join("index.html").read

      expect(index).to include('media="(max-width: 700px)"')
      expect(index).to include("images/2026-09-19-mobile.jpg")
    end

    it "marks portrait photos for aspect-ratio-preserving viewport sizing" do
      save_photo("2026-09-20", width: 1333, height: 2000)
      generator.generate!
      post = config.site_dir.join("posts/2026-09-20.html").read

      expect(post).to include('class="portrait-photo"')
    end

    it "defers feed images until the browser approaches them" do
      index = config.site_dir.join("index.html").read

      expect(index).to include('class="lazy-image')
      expect(index).to include('data-src="/images/2026-09-19.jpg"')
      expect(index).to include('width="1500" height="2000"')
      expect(index).to include('style="aspect-ratio: auto 1500 / 2000"')
      expect(config.site_dir.join("assets/site.js")).to exist
    end

    it "opens photos at full resolution while keeping date titles linked to posts" do
      index = config.site_dir.join("index.html").read
      post = config.site_dir.join("posts/2026-09-19.html").read

      expect(index).to include('<h1><a href="/posts/2026-09-19.html">')
      expect(index).to include(
        'class="photo-link lightbox-trigger" href="/images/2026-09-19.jpg"'
      )
      expect(post).to include(
        'class="photo-link lightbox-trigger" href="/images/2026-09-19.jpg"'
      )
      expect(index).to include('class="lightbox"')
      expect(index).to include('class="lightbox-image"')
    end

    it "adds an index-only back-to-top control" do
      index = config.site_dir.join("index.html").read
      about = config.site_dir.join("about.html").read
      post = config.site_dir.join("posts/2026-09-19.html").read

      expect(index).to include('class="back-to-top"')
      expect(index).to include('aria-label="Back to top"')
      expect(about).not_to include('class="back-to-top"')
      expect(post).not_to include('class="back-to-top"')
    end

    it "includes an accessible mobile calendar toggle before the About link" do
      index = config.site_dir.join("index.html").read
      toggle_position = index.index("calendar-toggle")
      about_position = index.index("about.html")

      expect(toggle_position).to be < about_position
      expect(index).to include('aria-controls="year-calendar"')
    end

    it "includes a configured Telegram channel after the RSS link" do
      linked_config = build_config(
        root:,
        telegram_channel_url: "https://t.me/photo_channel"
      )
      described_class.new(config: linked_config, store:, now: -> { now }).generate!
      index = linked_config.site_dir.join("index.html").read

      expect(index.index("feed.xml")).to be < index.index("https://t.me/photo_channel")
      expect(index).to include('href="https://t.me/photo_channel">Telegram</a>')
    end

    it "omits the Telegram menu item when no channel is configured" do
      index = config.site_dir.join("index.html").read

      expect(index).not_to include(">Telegram</a>")
    end

    it "folds next year's matching month into a red calendar layer" do
      save_photo("2027-09-17")
      generator.generate!
      index = config.site_dir.join("index.html").read

      expect(index).to include('<span class="calendar-year-later">/2027</span>')
      expect(index).to include('class="calendar-day has-photo later-year-photo"')
      expect(index).to include('href="/posts/2027-09-17.html"')
    end

    it "publishes absolute photo and post URLs in RSS" do
      feed = config.site_dir.join("feed.xml").read

      expect(feed).to include("https://photos.example.test/posts/2026-09-19.html")
      expect(feed).to include("https://photos.example.test/images/2026-09-19.jpg")
    end

    it "publishes image-rich social metadata and canonical URLs on every HTML page" do
      pages = [
        config.site_dir.join("index.html"),
        config.site_dir.join("about.html"),
        config.site_dir.join("posts/2026-09-19.html")
      ].map(&:read)

      expect(pages).to all(include('property="og:image"'))
      expect(pages).to all(include('name="twitter:card" content="summary_large_image"'))
      expect(pages).to all(include('rel="canonical"'))
      expect(pages.last).to include(
        'property="og:image" content="https://photos.example.test/images/2026-09-19.jpg"'
      )
    end

    it "uses the oldest photo as the index social cover" do
      save_photo("2026-09-20")
      generator.generate!
      index = config.site_dir.join("index.html").read

      expect(index).to include(
        'property="og:image" content="https://photos.example.test/images/2026-09-19.jpg"'
      )
      expect(index).not_to include(
        'property="og:image" content="https://photos.example.test/images/2026-09-20.jpg"'
      )
    end

    it "lists public pages and full-resolution photos in the sitemap" do
      sitemap = config.site_dir.join("sitemap.xml").read

      expect(sitemap).to include("https://photos.example.test/")
      expect(sitemap).to include("https://photos.example.test/about.html")
      expect(sitemap).to include("https://photos.example.test/posts/2026-09-19.html")
      expect(sitemap).to include("https://photos.example.test/images/2026-09-19.jpg")
    end

    it "allows search indexing while excluding named AI crawlers" do
      robots = config.site_dir.join("robots.txt").read

      expect(robots).to include("User-agent: *\nAllow: /")
      expect(robots).to include("User-agent: GPTBot\nDisallow: /")
      expect(robots).to include("User-agent: Google-Extended\nDisallow: /")
      expect(robots).to include("User-agent: ClaudeBot\nDisallow: /")
      expect(robots).to include("Sitemap: https://photos.example.test/sitemap.xml")
    end
  end

  def save_photo(date, width: 1500, height: 2000)
    store.images_dir.join("#{date}.jpg").write("desktop")
    store.images_dir.join("#{date}-mobile.jpg").write("mobile")
    store.save_photo(
      date:,
      image: "images/#{date}.jpg",
      mobile_image: "images/#{date}-mobile.jpg",
      width:,
      height:
    )
  end
end
