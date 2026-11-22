# DueIt

DueIt is a comprehensive productivity and due-management application designed to track tasks, habits, and financial obligations. Built on a robust Flutter front-end with a scalable Supabase backend, DueIt seamlessly unifies your day-to-day productivity needs.

## Features

- **Tasks**: Create, manage, and complete daily tasks.
- **Task Priorities**: Categorize tasks by priority levels.
- **Streak Tasks**: Build habits with consecutive-day streak tracking.
- **IST-Aware Streak Tracking**: Correctly calculates streak boundaries based on Asia/Kolkata (IST) time.
- **Dues (Lent / Borrowed)**: Keep track of financial obligations directionally.
- **Due Statuses**: Monitor dues across Pending, Settled, and Overdue states.
- **Notes**: Capture quick thoughts and reference material.
- **Personal Expenses**: Record and monitor day-to-day personal expenses.
- **Smart Inbox**: A unified, date-aware view of upcoming items.
- **JSON Export**: Export your data securely to JSON format.
- **Firebase Cloud Messaging Infrastructure**: Reliable push notification delivery mechanism.
- **Automated Reminder Generation**: System-level generation of pending reminder events.
- **Supabase Edge Functions**: Secure backend logic for integrations.
- **pg_cron Reminder Scheduling**: Automated periodic reminder dispatch.

## Reminder Architecture

Reminders in DueIt follow a decoupled, asynchronous generation and delivery pipeline:

Task / Due -> `reminder_events` (Table) -> `generate-reminders` (Edge Function) -> `pg_cron` -> `pg_net` -> `send-fcm-notification` (Edge Function) -> Firebase FCM -> User Device

**Reminder Timings:**
- **Upcoming**: Triggered exactly 24 hours before the due date.
- **Deadline**: Triggered at the exact due time (with a 15-minute tolerance window).
- **Overdue**: Triggered 1 hour after the due time. (Overdue reminders are sent once and do not recur.)

**Backlog Protection:** The reminder generator is designed to be resilient against scheduler outages. It actively filters out stale historical reminders to prevent users from receiving a massive backlog of notifications if the periodic cron job temporarily fails.

## Timezone Architecture

DueIt separates absolute storage time from business logic time.

- **Business Timezone**: Asia/Kolkata (IST)
- **Database Storage**: Absolute UTC timestamps (`timestamptz`).

Business/calendar calculations, streak boundaries, Smart Inbox date classifications, and task/due event creation all enforce IST boundaries. For example, midnight (00:00) IST correctly rolls over calendar days for streak evaluation, while the underlying data strictly relies on UTC-safe storage. Reminder scheduling operates safely on these absolute timestamps.

## Technology Stack

- **Client**: Flutter, Dart
- **Backend**: Supabase (PostgreSQL), Supabase Edge Functions, Supabase Vault
- **Scheduling/Networking**: pg_cron, pg_net
- **Push Notifications**: Firebase Cloud Messaging (FCM)
- **Timezone Management**: `timezone`, `flutter_timezone`
- **Local Storage**: `shared_preferences`

## Project Structure

```text
DueIt/
├── due_it/                # Flutter client application
│   ├── lib/               # Application source code
│   ├── test/              # Unit and widget tests
│   ├── android/           # Android platform scaffolding
│   ├── ios/               # iOS platform scaffolding
│   └── web/               # Web platform scaffolding
├── supabase/
│   ├── functions/         # Supabase Edge Functions (generate-reminders, send-fcm-notification)
│   └── migrations/        # Database schema and RLS policies
```

## Local Development

### 1. Prerequisites
- Flutter SDK
- Supabase CLI (optional, for local backend)
- Firebase CLI (optional, for advanced Firebase configs)

### 2. Repository Setup
Clone the repository and enter the Flutter directory:
```bash
git clone <repository_url>
cd DueIt/due_it
flutter pub get
```

### 3. Supabase Configuration (Client)
The application connects to a Supabase project. The `SUPABASE_URL` and `SUPABASE_ANON_KEY` are safely configured for the client in `lib/main.dart` (or via environments). Do **not** place Service Role keys in the client code.

### 4. Firebase Configuration
Firebase configuration for Android relies on `google-services.json` placed in `android/app/`. Web messaging relies on `firebase_options.dart` and the service worker in `web/firebase-messaging-sw.js`. 
For Web Push, provide the VAPID key at build time:
```bash
flutter build web --dart-define=FIREBASE_VAPID_KEY=your_vapid_key
```

### 5. Running the App
```bash
flutter run
```

## Supabase Setup (Server-side)

The Supabase backend relies on PostgreSQL tables (`tasks`, `dues`, `streak_tasks`, `reminder_events`, `user_fcm_tokens`, etc.) heavily secured by Row Level Security (RLS) policies.

Edge Functions require secrets to be set in your Supabase project:
- `SUPABASE_SERVICE_ROLE_KEY`
- `SCHEDULER_SECRET`
- `FIREBASE_SERVICE_ACCOUNT_JSON`

## Firebase Setup

Firebase handles the last mile of notification delivery. 
- FCM handles messaging to devices.
- `firebase-messaging-sw.js` enables background notifications on the web.
- Service Account JSON must only be provided to the Supabase Edge Function (`send-fcm-notification`), never the Flutter client.

## Deployment

The system is deployed in distinct layers:
1. **Flutter Client**: Deployed to standard app stores or web hosting.
2. **Supabase Backend**: Migrations applied to the production PostgreSQL instance.
3. **Supabase Edge Functions**: Deployed via Supabase CLI.
4. **Firebase FCM**: Operates as the push gateway.

*Note: Reminder scheduler configuration is provided through Supabase pg_cron/pg_net infrastructure. Live scheduler verification should be performed in the deployed Supabase environment.*

### Vercel Web Preview and Deployment

The repository includes a Vercel configuration for the Flutter web client. Import the repository into Vercel and leave the project root set to the repository root. Vercel runs `vercel-build.sh`, builds `due_it/` for web, and serves the output from `due_it/build/web`. The build script uses Flutter from `PATH` or `FLUTTER_ROOT`; if unavailable, it downloads the current stable Linux Flutter SDK.

Vercel's Git integration creates a preview deployment for each pull request and branch deployment URLs for commits. The rewrite configuration also sends deep links to Flutter's `index.html` entry point. To enable web push, set `FIREBASE_VAPID_KEY` in Vercel's Environment Variables for the relevant environments. Firebase's web client configuration in `web/firebase-messaging-sw.js` must also be filled in with the public Firebase project values; keep service-account credentials and Supabase service-role keys out of Vercel client environment variables.

## Security

DueIt employs a strict separation of concerns regarding credentials:
- **Server-side secrets are never stored in Flutter.**
- Supabase Service-Role credentials belong ONLY on trusted server-side environments (Edge Functions).
- Firebase Service-Account credentials belong ONLY in Edge Function secrets.
- Scheduler authorization secrets belong in Supabase Vault.
- `.env` files are ignored by version control.
- All multi-tenant user data is strictly isolated using Supabase RLS and ownership checks.

## Testing & Status

- `flutter analyze`: **PASS** (0 compilation errors, 18 infos/warnings)
- `flutter test`: **PASS**
- `flutter build web`: **PASS**
- Android Build: **BLOCKED** (Requires appropriate Android SDK in CI environment)
- Live `pg_cron` execution: **NOT VERIFIED / BLOCKED** (Pending live deployed environment)
- Live FCM end-to-end: **NOT VERIFIED** (Pending live deployed environment)

## Known Limitations

- Live `pg_cron` execution has not yet been verified in a production environment.
- Live FCM end-to-end delivery has not yet been verified.
- Android build verification requires a configured Android SDK environment.
- The current reminder delivery batch is intentionally limited to 100 pending events per 5-minute scheduler cycle to prevent rate-limit exhaustion.
