# 365

A Telegram bot and static-site generator for a 365 Project. The idea is that a
photographer takes one photo every day and publishes it as a visual diary.

Sending the bot an image publishes it as today's photo. At 21:00 in the configured timezone, the bot sends one reminder
if the day's image is missing. An optional notification channel receives the dated page URL at
22:00 when the photo is ready; if it is still missing then, a later photo is announced at 23:59.

The public site is only generated HTML, CSS, images, and RSS. It does not need an application
server. Each upload rebuilds every dated page, so the twelve-month calendar on old posts always
contains the latest links.

## Requirements

- Ruby 3.4.8
- ImageMagick 7 (`magick` on `PATH`) or ImageMagick 6 (`convert` and `identify` on `PATH`).
  The bot prefers `magick` and falls back automatically when it is unavailable. The installed
  version must support all configured resource limits, including `list-length`.
- A Telegram bot token from BotFather

## Setup

```sh
install -m 600 .env.example .env
# Edit .env, then load its values into the current shell.
set -a
. ./.env
set +a
bundle install
bundle exec bin/rebuild
bundle exec bin/365_bot
```

The bot only accepts messages from `TELEGRAM_CHAT_ID` sent by `TELEGRAM_USER_ID`. Both values are
required. Send a JPEG as either a Telegram photo or a JPEG image document. Other document formats
are rejected, and the downloaded file is independently verified as JPEG before ImageMagick reads
it. Sending a second image on the same day replaces that day's photo.

Set `TELEGRAM_NOTIFICATION_CHAT_ID` to a channel ID or public `@channelname` to enable daily URL
announcements. Add the bot to that channel as an administrator with permission to post messages.
For public usernames, the website's `Telegram` menu link is derived automatically. Set
`TELEGRAM_CHANNEL_URL` explicitly when the destination uses a numeric ID or an invite link.
Set `PROJECT_AUTHOR` to the name displayed in the website footer.

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

Point nginx, at `public/`. `SITE_URL` must
be the public root URL; subdirectory URLs are supported. The included systemd unit is an example
for keeping the bot running. It expects a dedicated `year-in-photos` user and group. Adapt its
paths and rbenv initialization to your server, and give the service account write access to
`DATA_DIR`, `SITE_DIR`, and the parent directory of `SITE_DIR`. The parent is needed because a
completed site is published by atomically replacing the previous output directory.
Keep the production `.env` file mode `0600`; it contains the Telegram bot token. The configured
`SITE_DIR` must be a dedicated generated-output directory and cannot contain the project or
`DATA_DIR`.

For nginx, the essential site block is:

```nginx
server {
  server_name photos.example.com;
  root /opt/365-photos/public;
  index index.html;
}
```

### systemd

Install the included unit on the server, then open it to confirm that its user, group, project
directory, and environment-file path match the deployment:

```sh
sudo install -m 0644 deploy/365-photos.service /etc/systemd/system/365-photos.service
sudo systemctl edit --full 365-photos.service
```

The supplied unit uses `year-in-photos:year-in-photos` and `/opt/365-photos`. If the project runs
as a different account or from another directory, update `User`, `Group`, `WorkingDirectory`, and
`EnvironmentFile`. Ensure the selected service account can run the configured Ruby and write
to `DATA_DIR`, `SITE_DIR`, and the parent directory of `SITE_DIR`. Keep the environment file
private:

```sh
sudo chmod 0600 /opt/365-photos/.env
sudo -u year-in-photos /bin/bash -lc \
  'cd /opt/365-photos && ruby --version && bundle check'
```

For deployments below `/home`, `ProtectHome=read-only` requires an explicit writable path in the
unit. Add the absolute project directory, which must include the site directory's parent because
publishing creates a staging directory beside `SITE_DIR` before atomically replacing it:

```ini
[Service]
ReadWritePaths=/absolute/path/to/365-photos
```

After adapting the paths and account, load, enable, and start the service:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now 365-photos.service
sudo systemctl status 365-photos.service
```

Use the journal to inspect startup failures or follow the running bot's output:

```sh
sudo journalctl -u 365-photos.service -n 100 --no-pager
sudo journalctl -u 365-photos.service -f
```

After changing the unit, run `systemctl daemon-reload` and restart it with
`sudo systemctl restart 365-photos.service`.

## Development

```sh
rbenv exec bundle exec rspec
rbenv exec bundle exec rubocop
```

## License

This project is available under the [MIT License](LICENSE).
