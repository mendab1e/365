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

      generator.generate!

      expect(config.site_dir.join("posts/2026-09-19.html")).not_to exist
      expect(config.site_dir.join("images/2026-09-19.jpg")).not_to exist
      expect(config.site_dir.join("images/2026-09-19-mobile.jpg")).not_to exist
    end

    it "copies only referenced images, excluding replacement backups and staging files" do
      %w[.photo.backup-token.jpg .photo.uploading-token.jpg orphan.jpg].each do |name|
        store.images_dir.join(name).write("unpublished")
      end

      generator.generate!

      expect(config.site_dir.join("images").children.map { |path| path.basename.to_s })
        .to contain_exactly("2026-09-19.jpg", "2026-09-19-mobile.jpg")
    end

    it "preserves the live site when a referenced image is missing" do
      original_index = config.site_dir.join("index.html").read
      store.images_dir.join("2026-09-19-mobile.jpg").delete

      expect { generator.generate! }.to raise_error(Errno::ENOENT)

      expect(config.site_dir.join("index.html").read).to eq(original_index)
      expect(config.site_dir.join("images/2026-09-19-mobile.jpg").read).to eq("mobile")
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

    it "renders usable fallback and dated-page pictures without deferred loading" do
      index = config.site_dir.join("index.html").read
      fallback = index.match(%r{<noscript>(.*?)</noscript>}m)[1]
      post = config.site_dir.join("posts/2026-09-19.html").read

      [fallback, post].each do |html|
        expect(html).to include('src="/images/2026-09-19.jpg"')
        expect(html).to include('srcset="/images/2026-09-19-mobile.jpg"')
        expect(html).to include('width="1500" height="2000"')
        expect(html).not_to include("data-src", "lazy-image")
      end
      expect(fallback).to include('loading="lazy"')
      expect(post).not_to include('loading="lazy"', "<noscript>")
    end

    it "keeps canonical URLs distinct from output filenames below a site subpath" do
      nested_config = build_config(root:, site_url: "https://photos.example.test/project")
      described_class.new(config: nested_config, store:, now: -> { now }).generate!

      { "index.html" => "", "about.html" => "about.html",
        "posts/2026-09-19.html" => "posts/2026-09-19.html" }.each do |file, path|
        html = config.site_dir.join(file).read
        expect(html).to include(
          %(<link rel="canonical" href="https://photos.example.test/project/#{path}">)
        )
      end
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

    it "groups RSS and a configured Telegram channel in a mobile Subscribe menu" do
      linked_config = build_config(
        root:,
        telegram_channel_url: "https://t.me/photo_channel"
      )
      described_class.new(config: linked_config, store:, now: -> { now }).generate!
      index = linked_config.site_dir.join("index.html").read

      expect(index).to include('<details class="subscribe-menu">')
      expect(index).to include("<summary>Subscribe</summary>")
      submenu = index.match(%r{<span class="subscribe-submenu">(.*?)</span>}m)[1]
      expect(submenu.index("feed.xml")).to be < submenu.index("https://t.me/photo_channel")
      expect(submenu).to include('href="/feed.xml">RSS</a>')
      expect(submenu).to include('href="https://t.me/photo_channel">Telegram</a>')

      styles = linked_config.site_dir.join("assets/style.css").read
      expect(styles).to include(".desktop-subscription-link {\n    display: none;")
      expect(styles).to include(".subscribe-menu {\n    display: block;")
      expect(styles).to include(".subscribe-menu[open] .subscribe-submenu {\n    display: grid;")
    end

    it "renders RSS directly and omits Subscribe when no Telegram channel is configured" do
      index = config.site_dir.join("index.html").read

      expect(index).to include('href="/feed.xml">RSS</a>')
      expect(index).not_to include(">Telegram</a>")
      expect(index).not_to include('class="subscribe-menu"')
    end

    it "includes the configured author and GitHub repository in the footer" do
      index = config.site_dir.join("index.html").read
      styles = config.site_dir.join("assets/style.css").read

      expect(index).to include("© Example Author")
      expect(index).to include('href="https://github.com/mendab1e/365"')
      expect(index).to include('class="github-link"')
      expect(index).to include("<span>365 - one photograph, every day, for a year</span>")
      expect(index).to include('<svg viewBox="0 0 16 16" aria-hidden="true">')
      expect(styles).to include("footer {\n  align-items: center;")
      expect(styles).to include(".site-footer {\n    column-gap: 16px;")
      expect(styles).to include("justify-content: flex-start;")
      expect(styles).to include("padding-right: 76px;")
      expect(styles).to include(".footer-copyright {\n    text-align: left;")
      expect(index.index('class="github-link"')).to be < index.index('class="footer-copyright"')
    end

    it "centers photographed dates inside compact calendar rectangles" do
      styles = config.site_dir.join("assets/style.css").read

      expect(styles).to include(".calendar-day.has-photo {")
      expect(styles).to include("border-radius: 2px;")
      expect(styles).to include("display: grid;")
      expect(styles).to include("font-variant-numeric: tabular-nums;")
      expect(styles).to include("line-height: 1;")
      expect(styles).to include("place-items: center;")
      expect(styles).to include("transform: translateY(-1px);")
      expect(styles).to include("width: 18px;")
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
