# KoraVuba — standalone mobile app (v2)

## 📲 Download

* **Android:** open the [latest release](../../releases/latest) on your phone,
  download **KoraVuba-N.apk**, open it and tap **Install**. Allow
  "Install unknown apps" for your browser if asked.
* **iPhone:** see [INSTALL_ON_IPHONE.md](INSTALL_ON_IPHONE.md). It needs a PC
  and Sideloadly; Apple does not allow installing from a browser.

---

Android / iOS app built with Flutter in the new **vubaVibe** design style (dark
slate + emerald, role colours), branded **KoraVuba**.

**No server and no API.** The app ships with its own database: a SQLite copy
of your MySQL dump `globalconnect_db.sql` (20 Apr 2026). It has the same
tables and the same column names as the Django project. On first launch the
database is copied to the phone, and everything (sign-ups, bookings, payments,
chats, reviews) is saved there.

---

## 1. Run it (Windows, step by step)

You need Flutter 3.35 or newer (`flutter --version`), Android Studio with an
emulator, and JDK 17.

```powershell
# 1. unzip to a short path OUTSIDE OneDrive, e.g. C:\dev\koravuba_app
cd C:\dev\koravuba_app

# 2. get the packages
flutter pub get

# 3. start an emulator (or plug in a phone with USB debugging on)
flutter emulators --launch <emulator_id>     # list ids with: flutter emulators

# 4. run
flutter run
```

If Gradle says *"Unable to delete directory … build"*, run:

```powershell
cd android; .\gradlew --stop; cd ..
flutter clean
flutter pub get
flutter run
```

Build an installable APK: `flutter build apk --release`. The APK is written to
`build\app\outputs\flutter-apk\app-release.apk`.

---

## 2. Accounts and starting your own data

The bundled database is **completely empty**. It has all the Django tables,
and only one row of data: the **HQ admin** account. Its credentials are
shared privately by the project owner. Long-press the logo to sign in, then
change the password in Control. Django's internal `django_migrations` and `django_content_type`
records are kept; they describe the schema and are not data.

**First, as HQ:** open **Control → Service categories** and add the services
workers can offer (name, price and unit, kind, colour). Workers cannot
register until at least one category exists. Commission (9%) and deposit
(50%) use these defaults until you change them in Control.

**Entering your own data through the app:**

1. **Company tab → Create Account**: register each company.
2. **HQ** (long-press the logo, `admin@gmail.com`) → Companies → **Verify &
   approve**. The company receives its Company ID (`KV-COMP-101`, …).
3. **Worker tab → Create Account** with that Company ID. The worker gets a
   badge ID.
4. **Company tab** → Workers → Applications → **Approve badge**. The worker can
   now sign in and go **Online**.
5. **Client tab → Create Account**. Clients can now book.

Build options for `tools/build_db.py`, set as environment variables:

* `ONLY_HQ=1` keeps only the HQ login. This is how the bundled database was
  made.
* `FRESH=1` does the same but keeps the 10 default categories.
* `HQ_PASSWORD=...` sets the HQ password.
* Without `FRESH=1`, all your MySQL data is kept.
* `DEMO=1` adds the design's demo companies, workers and logins.

## 3. What each role can do

| Role | Tabs (top icon bar, no side bar) |
|---|---|
| **Client** (emerald) | Home: radius 1–25 km, category filter, **orbital radar** / street map, nearby and top providers · Messages · Notifications · Activities (search, filters, audit) · Profile (photo, MoMo number, Kigali sector, password, dark/light) |
| **Worker** (amber) | Dispatch dashboard: online switch, incoming requests (accept/decline), active jobs, earnings · Messages · Notifications · Job history · Profile + badge |
| **Company** (blue) | Overview (revenue, 91% net, payouts, Company ID) · Workers (team, approve applications, mute/reactivate, edit rates) · Notifications · Bookings · Company profile |
| **HQ admin** (purple) | Overview (GMV, 9% fee, net pool, approval queue, SOS alerts, **19:00 payout**) · Companies (verify / reject / suspend) · Workers · Ledger · Control (commission %, deposit %, users, reset database) |

Booking details include a live timeline and job timer, chat, call, an **SOS**
button (alerts HQ and the company, then offers to call 112), problem reports
(saved in `disputes`), payments and an audit trail.

Sign-ups:

* **Client** — creates the account and signs in.
* **Worker** — needs the company's ID (e.g. `KV-COMP-101`). It creates a badge
  and a `provider_applications` row. The worker can sign in once the company
  approves it.
* **Company** — HQ verifies it and assigns a `KV-COMP-…` ID.

---

## 4. The database

```
assets/db/koravuba.db        bundled SQLite copy (copied to the phone on first launch)
tools/build_db.py            script that produced it from MySQL
```

* **All Django tables, same names and columns:** `users`, `provider_profiles`,
  `provider_services`, `bookings`, `transactions`, `chat_conversations`,
  `chat_messages`, `notifications`, `reviews`, `disputes`, `entities`,
  `entity_admins`, `provider_applications`, … IDs are Django's 32-character
  UUID hex and dates are Django's format, so rows can be sent back to MySQL
  as they are.
* **Your data:** every row from your dump is included (12 users, 30 bookings,
  138 messages, 216 notifications, reviews, disputes, …).
  * Two kinds of rows were left out because the app does not need them:
    sessions and admin logs.
  * The 10 service categories were added (no demo companies, workers or
    accounts).
  * Your existing services were mapped to categories by name. Check the
    mapping, because some are guesses.
* **App-only tables** (prefix `kv_`, ignored by Django):
  * `kv_settings`: commission 9%, deposit 50%.
  * `kv_badges`: worker badge IDs.
  * `kv_category_meta`: Kinyarwanda names and prices.
  * `kv_sos_alerts`, `kv_user_settings`: SOS alerts and each user's MoMo
    number and sector.
  * `kv_sync_log`: every insert, update and delete made on the phone.
* **Money rule (from the design):**
  * The client pays the service price, with 50% up front by MoMo and the rest
    after the job.
  * KoraVuba keeps 9% (`bookings.platform_fee`). The company or provider gets
    91% (`provider_earnings`).
  * Every payment, refund and payout is written to `transactions`.
* **Payments are simulated:** no real MoMo request is sent. Connect the real
  MTN MoMo / Airtel APIs when you add the server.
* **Reset:** HQ admin → Control → *Reset to the bundled database*.

### Rebuilding the database from a newer MySQL dump

```bash
# import the dump into MySQL/MariaDB as globalconnect_db, run Django migrations, then:
pip install mysqlclient
python tools/build_db.py assets/db/koravuba.db
```

Phones that already have the app keep their own copy. Uninstall the app, or
use *Reset*, to load the new one.

---

## 5. Later: connecting your web app (API)

The code is split so the database layer can be swapped without touching the
screens:

```
lib/core/db.dart         AppDb: open / insert / update / delete (+ kv_sync_log)
lib/data/*_repo.dart     all reads & writes (auth, catalog, bookings, chat, company, admin)
lib/features/**          screens only call the repos
```

When your Django API is ready:

1. Expose endpoints for the same tables. The JWT add-on delivered with v1
   (`backend_mobile_api`) is a starting point.
2. Upload new rows. Read `kv_sync_log` (table + row id + action), post those
   rows to the API, then delete the log entries. The ids are UUIDs, so they
   never collide with server ids.
3. Pull changes. Download rows changed since the last sync (`updated_at`) and
   upsert them into SQLite.
4. Or move fully online. Replace the bodies of the repo methods with HTTP
   calls; the screens stay the same.

---

## 6. Project structure

```
lib/
├── main.dart, app.dart            start-up, theme, role gate
├── core/   db.dart · django_password.dart · session.dart · theme.dart · format.dart · geo.dart
├── data/   models.dart · auth_repo · catalog_repo · booking_repo · chat_repo · notify · org_repo · worker_repo
├── widgets/ common.dart (cards, tags, buttons, fields…) · role_shell.dart (top icon navigation)
└── features/
    ├── auth/login_portal.dart           Client / Worker / Company + sign-up + hidden HQ entry
    ├── client/  home · radar & map painters · worker sheet · booking flow + receipt · activities
    ├── worker/  dispatch dashboard
    ├── company/ overview · workers & applications · company profile
    ├── admin/   HQ overview · companies · workers · ledger · control
    └── shared/  messages/chat · notifications · booking detail · MoMo checkout · profile
test/app_test.dart   password hashing (RFC vectors + a Python-made Django hash), formatting, distance
```

Run the tests with `flutter test`.

## 7. Troubleshooting

* **`initialValue` isn't defined** (DropdownButtonFormField): your Flutter is
  older than 3.35. Run `flutter upgrade`, or replace `initialValue:` with
  `value:` in the 3 dropdowns.
* **Gradle / Kotlin version errors:** run `flutter create --platforms=android,ios .`
  inside the project. It regenerates only missing files; keep `lib/`, `assets/`
  and `pubspec.yaml`.
* **Login is slow (about 1 s):** this is normal. Django hashes use 600 000
  PBKDF2 rounds and the check runs in the background.
* **Emulator shows old data after you replace the database:** uninstall the
  app or use *Reset*.
