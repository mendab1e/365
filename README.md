# 365 Days

A Telegram bot and static-site generator for a daily photo project. Sending the bot an image
publishes it as today's photo. At 21:00 in the configured timezone, the bot sends one reminder
if the day's image is missing. An optional notification channel receives the dated page URL at
22:00 when the photo is ready; if it is still missing then, a later photo is announced at 23:59.

The public site is only generated HTML, CSS, images, and RSS. It does not need an application
server. Each upload rebuilds every dated page, so the twelve-month calendar on old posts always
contains the latest links.

## Requirements

- Ruby 3.4.8 managed by rbenv
- ImageMagick 7 (`magick` on `PATH`)
- A Telegram bot token from BotFather
- A static web server or static hosting provider

## Setup

```sh
cp .env.example .env
# Edit .env, then load its values into the current shell.
set -a
. ./.env
set +a
rbenv exec bundle install
rbenv exec bundle exec bin/rebuild
rbenv exec bundle exec bin/365_bot
```

The bot only accepts messages from `TELEGRAM_CHAT_ID`. Set `TELEGRAM_USER_ID` as an additional
sender check, especially if the bot is used in a group. Send an image as either a Telegram image
or an image document. Sending a second image on the same day replaces that day's photo.

Set `TELEGRAM_NOTIFICATION_CHAT_ID` to a channel ID or public `@channelname` to enable daily URL
announcements. Add the bot to that channel as an administrator with permission to post messages.
For public usernames, the website's `Telegram` menu link is derived automatically. Set
`TELEGRAM_CHANNEL_URL` explicitly when the destination uses a numeric ID or an invite link.

Available commands:

- `/status` — report whether today's image exists and the total photo count
- `/rebuild` — regenerate the static site from stored metadata and processed images

## Generated files and image handling

Processed source-of-truth images and JSON metadata are stored under `data/`. The generated site
is written to `public/`; both are ignored by Git. Back up `data/`.

ImageMagick auto-orients and strips metadata from incoming images. The desktop variant fits inside
2000×2000 and the mobile variant fits inside 900×1800. Both retain aspect ratio and use quality
80. For example, a 3000×4000 image becomes 1500×2000. The downloaded original is a temporary file
and is deleted immediately after processing.

The calendar covers twelve consecutive months beginning with the month of the first upload. Before
the first upload it begins with the current month.

## Hosting

Point nginx, Caddy, an object-storage static host, or any equivalent at `public/`. `SITE_URL` must
be the public root URL; subdirectory URLs are supported. The included systemd unit is an example
for keeping the bot running. It expects a dedicated `year-in-photos` user and group. Adapt its
paths and rbenv initialization to your server, and give the service account write access to
`DATA_DIR`, `SITE_DIR`, and the parent directory of `SITE_DIR`. The parent is needed because a
completed site is published by atomically replacing the previous output directory.

For nginx, the essential site block is:

```nginx
server {
  server_name photos.example.com;
  root /opt/365-photos/public;
  index index.html;
}
```

## Development

```sh
rbenv exec bundle exec rspec
rbenv exec bundle exec rubocop
```
