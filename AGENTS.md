# 365 Days — Agent Guide

## Purpose

This repository is a Ruby Telegram bot plus a static-site generator for a daily photo project.
One authorized user sends a photo to the bot each day. The bot processes the image, records the
day, and rebuilds a static website. At the configured reminder hour, it sends one Telegram reminder
if that day's photo is missing. An optional notification channel receives the dated page URL at
22:00 if the photo is present, or at 23:59 when the photo was missing at 22:00.

The deployed website must remain static: HTML, CSS, JavaScript, images, and RSS only. Do not add a
web application server, database, client-side framework, or build pipeline unless the user changes
that requirement. A temporary loopback-only static server is acceptable for local previewing.

## Runtime and development rules

- Ruby is pinned by `.ruby-version` and must always run through rbenv.
- Production image processing requires ImageMagick 7 and the `magick` executable.
- Use RSpec for behavior tests and RuboCop for Ruby style.
- Run the full verification commands after code or template changes:

  ```sh
  rbenv exec bundle exec rspec
  RUBOCOP_CACHE_ROOT=/private/tmp/365-rubocop-cache rbenv exec bundle exec rubocop
  ```

- `data/` and `public/` are ignored runtime/generated directories. Never assume they are committed.
- Do not delete or modify a user's original source photo. Telegram downloads are temporary files;
  test imports from local paths must leave those originals untouched.
- Do not expose private photos by binding previews to `0.0.0.0`. Bind local previews to
  `127.0.0.1` only.

## Architecture

The entry point is `bin/365_bot`. It constructs shared services and starts two long-lived loops:

1. Telegram long polling receives messages and dispatches commands or image uploads.
2. A scheduling thread checks every 30 seconds for the missing-photo reminder and the optional
   22:00/23:59 notification-channel publication.

The upload pipeline is:

```text
Telegram update
  -> TelegramClient downloads into a Tempfile
  -> ImageProcessor creates desktop and mobile JPEG variants
  -> PhotoStore atomically updates JSON metadata
  -> SiteGenerator rebuilds all static pages and RSS
  -> Tempfile block removes the downloaded original
```

Uploads are serialized with a mutex. Sending another image on the same date replaces that day's
processed files and metadata. Image replacements are produced in staging files first, so a failed
conversion does not remove the currently working images.

### Main components

- `lib/year_in_photos/config.rb` — reads environment configuration, sets `TZ`, validates URLs and
  sizing, and handles optional site subpaths.
- `lib/year_in_photos/telegram_client.rb` — small standard-library Telegram Bot API client for
  long polling, messages, file lookup, and download.
- `lib/year_in_photos/bot.rb` — authorization, commands, upload orchestration, retry loops, and
  reminder scheduling.
- `lib/year_in_photos/image_processor.rb` — shells out safely to ImageMagick without a shell string.
- `lib/year_in_photos/photo_store.rb` — JSON metadata, reminder state, and channel-notification
  state with atomic renames.
- `lib/year_in_photos/calendar.rb` — creates twelve consecutive month grids beginning with the
  month of the first upload.
- `lib/year_in_photos/site_generator.rb` — renders ERB templates, copies processed images/assets,
  rewrites every dated page, and generates RSS, sitemap, and crawler policy files.
- `templates/` — source templates and browser assets. Edit these, not files under `public/`.
- `bin/rebuild` — regenerates the static site from `data/` without requiring Telegram credentials.

## Persistent and generated data

`data/` is the source of truth and must be backed up in production:

- `data/photos.json` — sorted photo records with date, image paths, and desktop dimensions.
- `data/reminders.json` — dates for which a reminder was already sent.
- `data/notifications.json` — dates whose channel publication was deferred or completed.
- `data/images/YYYY-MM-DD.jpg` — desktop image.
- `data/images/YYYY-MM-DD-mobile.jpg` — mobile image.

`public/` is disposable generated output:

- `index.html` — newest-first feed.
- `posts/YYYY-MM-DD.html` — permanent page for one day.
- `about.html` — placeholder About page.
- `feed.xml` — RSS 2.0 feed with absolute URLs.
- `sitemap.xml` — index, About page, every dated post, and each post's desktop image.
- `robots.txt` — allows ordinary search crawling, links the sitemap, and disallows named AI agents.
- `assets/` and `images/` — copied browser assets and processed photos.

Every upload regenerates every dated page. This is intentional: old post pages then receive the
latest calendar links without needing dynamic server rendering. Generator writes go into a private staging directory, which SitePublisher installs only after
all files are complete. Only images referenced by photo records are copied to the site. `SiteGenerator#generate!` clears its memoized photo/calendar data
at the start because the same instance is reused by the long-running bot.

## Image contract

- Auto-orient and strip metadata.
- Accept JPEG/JPG input only, verify the JPEG signature, and force ImageMagick's JPEG decoder.
- Apply ImageMagick width, height, area, memory, map, disk, file, thread, time, and list limits
  before decoding an upload.
- Preserve aspect ratio and never upscale (`-resize SIZE>`).
- Desktop bounds: 2000×2000.
- Mobile bounds: `MOBILE_IMAGE_SIZE`, default 900×1800.
- JPEG quality: 80, progressive interlacing enabled.
- Use only the first frame/page of a submitted image.
- The desktop width and height are stored for stable browser layout.

## Website behavior

- Minimal light-grey responsive design.
- Feed is sorted newest first; each entry clearly labels and links its date.
- The twelve-month calendar is visible on desktop. Dates with photos are bold links inside dark
  circular markers; missing dates are plain, non-clickable text. Desktop rows are deliberately
  compact so the calendar does not dominate the page.
- Photos uploaded in the same month of a later year are folded into the original month block. The
  heading gains a red suffix such as `September 2026/2027`, and later-year dates use red circles.
  If the same month/day has photos in multiple years, the latest year owns that calendar slot;
  older posts remain in the feed and retain their permanent pages.
- On screens at or below 700px, the calendar is hidden initially. A `Calendar` button before the
  About link toggles it and updates `aria-expanded`.
- Feed images use `data-src`/`data-srcset` plus `IntersectionObserver`; intrinsic `width` and
  `height` attributes plus an `auto` fallback aspect ratio prevent layout collapse while yielding
  to the loaded image's natural ratio. Keep the `<noscript>` fallback.
- Feed images are constrained by viewport height so a portrait photo fits within a desktop screen;
  width remains automatic to preserve aspect ratio.
- Clicking a feed photo opens the largest processed image in a full-screen modal with the white
  frame preserved. Clicking the feed date title opens that photo's permanent dated page. The
  full-screen viewer closes from its close button, backdrop, or Escape key.
- The index has a fixed circular `^` back-to-top button. It remains hidden until the page has
  scrolled beyond the calendar (or the collapsed header on mobile), then scrolls smoothly to the
  top while respecting reduced-motion preferences.
- Photos receive a uniform white CSS frame and a subtle shadow at render time: 30px on desktop and
  15px on mobile. Do not bake the frame into processed files; RSS, sitemap, and social cards should
  use the clean JPEG.
- Desktop and mobile images are selected with `<picture>`.
- The shared layout and calendar appear on the index, About page, and all dated posts.
- Every HTML page emits canonical, Open Graph, and large-image card metadata with absolute URLs.
  Dated posts use their own photo; the index and About page use the oldest photo as the project
  cover. Pages generated before the first upload fall back to a text-only summary card.
- `SITE_URL` is used for RSS absolute URLs. `Config#public_path` supports hosting below a URL path.
- `robots.txt` deliberately allows `User-agent: *` for search indexing, then blocks dedicated AI
  training, answer, retrieval, and user-fetch agents by their specific tokens. These directives are
  a voluntary signal and cannot prevent noncompliant bots or downstream use of search indexes.

## Bot behavior and security

- `TELEGRAM_CHAT_ID` is required and is always checked.
- `TELEGRAM_USER_ID` is required as an additional sender restriction.
- `TELEGRAM_NOTIFICATION_CHAT_ID` optionally receives a dated post URL. If the photo exists at
  22:00, the URL is sent then. If it is absent, that date is marked deferred and a later photo is
  announced at 23:59. No link is sent if the dated page still does not exist at 23:59.
- Channel publication state is persisted, so restarts do not duplicate announcements.
- Accepted uploads are Telegram photos and JPEG/JPG image documents. Other document formats are
  rejected, and downloaded content is independently verified before decoding.
- `/status` reports today's state and total photo count.
- `/rebuild` regenerates the site.
- Reminder state is persisted so process restarts do not resend the same day's reminder.
- Network and processing failures are logged and polling retries after five seconds.

## Configuration

See `.env.example`. Important values are:

- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `TELEGRAM_USER_ID`
- optional `TELEGRAM_NOTIFICATION_CHAT_ID` and `TELEGRAM_CHANNEL_URL`; a public `@channelname`
  automatically derives its `https://t.me/` menu link
- `PROJECT_TITLE`, `PROJECT_TIMEZONE`, `REMINDER_HOUR`
- `SITE_URL`, `SITE_DIR`, `DATA_DIR`, `MOBILE_IMAGE_SIZE`

The project does not automatically parse `.env`; load it in the shell or process manager. The
sample systemd unit uses `EnvironmentFile`.

## Tests

Specs mirror component boundaries:

- `calendar_spec.rb` — rolling month range and uploaded-date state.
- `photo_store_spec.rb` — same-date replacement, reminder persistence, and notification state.
- `image_processor_spec.rb` — ImageMagick arguments, bounds, and quality.
- `site_generator_spec.rb` — pages, RSS, current calendars on old pages, responsive assets, mobile
  toggle markup, and deferred image loading.
- `bot_spec.rb` — reminder timing plus 22:00/23:59 channel scheduling and deduplication.

When changing generated markup, update the template and generator spec, then run `bin/rebuild` to
refresh the local preview. Never edit `public/` directly because the next rebuild overwrites it.

## Current local fixture

The present ignored `data/` directory contains five black-and-white Japan test photos dated
September 15–19, 2026. They were imported from user-owned originals outside the repository. The
current ignored `public/` directory is the corresponding generated preview. This fixture is local
development state, not repository source and not a migration or seed mechanism.

For a local static preview:

```sh
rbenv exec ruby -run -e httpd public -p 4567 -b 127.0.0.1
```

Then open `http://127.0.0.1:4567/`.
