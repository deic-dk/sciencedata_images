# ubuntu_noble_moodle_sciencedata - Moodle on ScienceData

Internal documentation: how the image works and how it is tied into ScienceData.
User-facing guide: `pod_manifests/ubuntu_noble_moodle.guide.md` (shown by the Containers
app). Moodle branch: `MOODLE_503_STABLE` (5.3), cloned at build time.

## Purpose and intended use

A lecturer's own Moodle, started from the Containers app (user_pods) on kube. One
long-lived Moodle per lecturer, one ScienceData group per course; students log in with
their ScienceData accounts. Meant for smaller institutions and for trying things out -
DTU, KU and the like have their own learning platforms, which this does not replace.

## What runs in the pod

```
          kube.sciencedata.dk:<port>  (kube's Caddy: TLS, allowed-address rules)
                       |
   pod  +--------------v---------------------------------------------+
        | Caddy :80 -> PHP-FPM (Moodle, public/)   cron   dropbear :22 |
        | PostgreSQL 17 (database inside the pod)                      |
        | /var/moodledata  <- NFS: a folder of the owner's /storage    |
        +-------------------------------+------------------------------+
                                        |  https://sciencedata/...  (address login)
                       owner's home ScienceData server (user_pods, files, mail)
```

- **Address login.** Every call from the pod to ScienceData goes to `https://sciencedata`
  (an `/etc/hosts` entry for the owner's home server, kept by a cron line) and is
  authenticated by the pod's network address: ScienceData knows which pod, and so which
  owner, an address belongs to. No passwords or tokens are stored in the pod. The
  server's certificate names the public host, so host-name verification is off for these
  internal calls (curl `--insecure`, `CURLOPT_SSL_VERIFYHOST 0`).
- **Data.** The database lives in the pod and is backed up to the owner's files (below).
  Moodle's file store (`/var/moodledata`) is the mounted ScienceData folder, which must be
  writable (`/storage/...`); a read-only mount keeps the files in the pod and loses them
  with it (start.sh warns).

## Start and stop (start.sh)

At each start, in this order:

1. `sciencedata` in `/etc/hosts`; PHP upload limits (4 GB, 1 h) for course material.
2. Moodle's public address `https://kube.sciencedata.dk:<HTTPS_PORT>` into `config.php`,
   and a session cookie named after the port - all pods share the host name, and browsers
   keep cookies per host, so two Moodles would otherwise log each other out.
3. PostgreSQL starts; the last database dump is restored from
   `Containers/moodle_db-<mount folder>.sql.gz` in the owner's files (404 = new site).
   If ScienceData cannot be reached, the pod starts but **does not back up at shutdown**,
   so an empty state never overwrites a good backup.
4. A new site gets Moodle's preinstalled files, a random admin password, the owner's
   address as support address and a fresh site identifier. `admin/cli/upgrade.php` runs
   every time (newer image, older database).
5. Login: the pod asks user_pods for its login client (`api/pod-login`) and configures
   "Log in with ScienceData" (`sciencedata_oidc.php`). Groups become cohorts and courses
   (`sciencedata_cohorts.php`, then every 5 minutes).
6. Course material folders in the owner's files (`sciencedata_course_folders.php`),
   the transcoding cron job, and Moodle's settings for the ScienceData plugins
   (`sciencedata_setup.php`).
7. Without ScienceData login, until admin has logged in once: the pod's link on the
   Containers page is Moodle's own set-password page (a reset token, refreshed by cron).
8. Caddy starts; `/tmp/URI` tells the Containers app the pod is ready (the manifest's
   `catalog/wait-for-token`).

**Stop.** Kubernetes sends SIGTERM to start.sh, which dumps the database and uploads it
(`moodle_backup.sh`); the manifest allows 600 s for this. A dump is also made hourly by
cron, so a pod that dies without a clean stop loses at most an hour. A pod restarted on the
same `/storage` folder continues where it stopped: database from the dump, files on NFS.

## Login and accounts

- **OpenID Connect against the owner's ScienceData server**, with a client user_pods
  creates for this pod. Started for one or more groups: their members may log in and get a
  Moodle account at their first login. Started "just for me": only the owner, and no
  accounts are created.
- **The owner is Moodle's `admin`**, linked to their ScienceData ID.
- **Accounts are matched by ScienceData ID only, never by e-mail** (`oauth2_patch.sh`,
  applied at build; the build fails if Moodle's code changes shape). Moodle would
  otherwise link a login to any account with the same e-mail address, and Nextcloud users
  can set their own address - a takeover of `admin` would be one e-mail change away.
- Moodle's own login form stays, for local accounts the owner creates.
- The site is not registered with moodle.org (`$CFG->site_is_public`); see "Updates".

## Groups, cohorts and courses

`sciencedata_cohorts.php` (at start, then every 5 minutes) asks user_pods for the members
of each login group (`api/pod-members`) and:

- keeps a **cohort per group**; members without an account get one in advance (OAuth 2
  kind, filled in at their first login), so they can be enrolled before they log in;
  members who leave the group are removed from the cohort and so unenrolled;
- creates **one course per group**, once: named after the group, the cohort enrolled as
  students (cohort sync), the owner as teacher, with a "ScienceData folder" activity on the
  group's course-material folder. Remembered per group (`sciencedata_courses`), so a course
  the owner renames or deletes is not recreated.

## Course material: one home, on ScienceData

The folder **`Course material`** in the owner's ScienceData files, with a subfolder per
group (made and shared read-only with that group at first start, then left to the owner).
It is an ordinary ScienceData folder: web interface, sync client, sharing - and Moodle
reads it live. There are no copies to keep in sync:

- **ScienceData folder activity** (`mod_sciencedata`): lists a folder below
  `Course material`, read over WebDAV on each view. Teachers upload, make folders and
  delete straight on ScienceData; students download through Moodle
  (`download.php` streams with byte ranges, so videos can seek). Paths cannot leave the
  activity's folder (`classes/dav.php`). Moodle's own File and Folder activities are hidden
  from the activity chooser (existing ones keep working).
- **File picker** (`repository_sciencedata`): the same folder in Moodle's file picker, as a
  copy or as a reference Moodle refreshes from ScienceData (at most every 5 minutes, only
  if the file changed).
- **Links in course text** (`filter_sciencedata`): ScienceData share links become a
  notebook preview with "Run this notebook", a video player, or a folder card. What a link
  points to is asked once from the share's public WebDAV and cached for an hour.
- **Course backup and restore** include the activity's settings, not the files: they stay
  on ScienceData, and a restored or copied course points at the same folder.

## Videos: a web version for each

Phones and cameras produce videos browsers often cannot play (HEVC `.MOV`, large files, no
fast start). `sciencedata_transcode.php` runs every 5 minutes (cron, one run at a time):

- **Finds** videos in `Course material` (by extension: mp4, mov, mkv, webm, avi, ...).
- **Checks** each with `ffprobe`: already web-ready means MP4/WebM, H.264/VP8/VP9/AV1 video
  at most 1080 lines, AAC/MP3/Opus/Vorbis audio - those are left alone.
- **Converts at most one video per run**, at low priority:
  `ffmpeg ... -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -vf scale=-2:min(720,ih)
  -c:a aac -b:a 128k -ac 2 -movflags +faststart` - H.264/AAC, at most 720 lines,
  streamable from the start.
- **Stores** the result next to the original as `.web/<original name>.mp4` (a hidden folder,
  uploaded over WebDAV). A web version older than its original is made again; one whose
  original is gone is deleted. Originals found web-ready or failed are remembered by etag
  in `/var/moodledata/.sciencedata_transcode.json`.
- **The activity plays** the web version if there is one, else the original if browsers can
  play it; otherwise it says a web version is being prepared and offers the download.
  (0075, not merged yet: the page then reloads itself every minute.)

Measured 2026-11-25: a 3-minute phone video (234 MB `.MOV`) became a 30 MB MP4 (1280x720,
1.4 Mbit/s) in 51 s. Log: `/var/cache/moodle/transcode.log`.

## Mail

No mail server or credentials in the pod. PHP's `sendmail_path` is `sciencedata_sendmail`,
which hands each message to the owner's ScienceData server (`api/pod-mail`), which sends it
with its own mail settings and its no-reply sender. Limits per owner: max(20, 2 x group
size) messages per hour and max(100, 10 x group size) per day, plus a size limit
(user_pods `PodMail`).

## Performance and sizing

Load test 2026-11-25, 4-core node: 200 students logging in and opening the course and the
folder activity at the same moment - no errors at any level. Ubuntu's default 5 PHP-FPM
workers gave 21 req/s (~8-10 s per page) with the CPU half idle; 16 workers 35 req/s
(~5 s), then CPU-bound. PostgreSQL never had more than 4 active connections.

- Image (0076, not merged yet): 4 PHP-FPM workers per CPU, 8-64.
- Manifest (pod_manifests 0028, not merged yet): requests 4 CPUs, so Moodle runs on a node
  with room (worker1 48 cores, connect, peon141), not on a 4-core node.
- OPcache is on (128 MB).

## Updates

The site is unregistered, so nobody tells us about Moodle releases. security_watch on lab
(`MOODLE_BRANCH="5.3"`) reports each new 5.3 release in its daily mail; security fixes come
in these point releases. Then rebuild the image - the branch is cloned at build - and
restart the Moodle pods: `upgrade.php` brings the database up at start.

## Files

| File | Role |
|---|---|
| `Dockerfile` | Ubuntu 24.04, PostgreSQL 17, PHP 8.3-FPM, Caddy, ffmpeg; clones Moodle 5.3, preinstalls a site, copies the plugins |
| `start.sh` | everything at start and stop (above) |
| `config.php` | Moodle's config; wwwroot and session cookie set by start.sh |
| `Caddyfile` | the pod's web server, PHP-FPM for `public/` |
| `oauth2_patch.sh` | build: no linking of logins to accounts by e-mail |
| `sciencedata_oidc.php` | "Log in with ScienceData" from user_pods' answer |
| `sciencedata_cohorts.php` | groups -> cohorts and one course each |
| `sciencedata_course_folders.php` | `Course material` and the group folders in the owner's files |
| `sciencedata_setup.php` | Moodle settings for the plugins; hides File/Folder activities |
| `sciencedata_transcode.php` | web versions of videos |
| `sciencedata_sendmail` | mail through the owner's ScienceData server |
| `moodle_backup.sh` | database dump to `Containers/` (shutdown and hourly) |
| `mod_sciencedata/` | the ScienceData folder activity |
| `repository_sciencedata/` | the file picker |
| `filter_sciencedata/` | share links as previews, players, cards |

## Where to look

- Start-up messages: the pod's log in the Containers app (`kubectl logs`).
- Transcoding: `/var/cache/moodle/transcode.log`; backups: `/var/log/moodle_backup.log`.
- Moodle's own cron runs every minute (`/etc/cron.d/moodle`).
- Cron jobs written by start.sh: `moodle_cohorts`, `moodle_transcode`, `moodle_backup`,
  `moodle_admin_link`, `sciencedata_hosts` in `/etc/cron.d/`.

## Known gaps

- Mail at volume (a forum post to a whole large group) is not tested against the limits.
- The relayed mail's sender is ScienceData's no-reply address, not the teacher's.
- Per-user files in the file picker (students' own ScienceData files) are not offered.
