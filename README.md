
# HOLISTIC EDUCATIONAL ANECDOTAL RECORD & TRACKING SYSTEM

Fresh Flutter/Dart baseline for a Windows-first application that can later be ported to Android.

## Current foundation

- Flutter/Dart
- SQLite local database
- Windows SQLite initialization through `sqflite_common_ffi`
- Android-compatible database initialization through `sqflite`
- Six screens:
  - Home
  - Search
  - Add Learner
  - Teachers/Sections
  - View Learner
  - Print
- Password gate
- Change-password support
- Sync-pending counter
- Database tables for teachers, sections, learners, school history, incidents
- Automatic CreatedAt / UpdatedAt / DeviceID / Version / Deleted fields

## Important

Google Sheets synchronization, QR scanning, actual printing, and the full Philippine locations database are intentionally kept as the next implementation phase. The app must be tested locally first before adding cloud synchronization.

## Run

Before building a fresh checkout, supply your existing Desktop OAuth client
configuration at `assets/google/google_oauth_client.json`. This real file is
ignored by Git. `assets/google/google_oauth_client.example.json` documents the
required fields without credentials; its empty values cannot authenticate.
Do not overwrite an existing working configuration or commit the real file.

The real configuration is a required Flutter asset, so a checkout without it
cannot build until it is supplied locally. Deployment builds must also receive
this file locally before building. Flutter bundles it into the application;
excluding it from Git does not make it secret from users of the built desktop app.

```text
flutter pub get
flutter run -d windows
```

For Android later:

```text
flutter run -d android
```
