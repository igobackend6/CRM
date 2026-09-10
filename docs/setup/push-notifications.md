# Push Notifications (FCM) — setup

Push-on-assignment is **built and wired but dormant** — no Firebase
project is configured. Today, assigning a lead lands the in-app
notification (the `notifications` row + Realtime badge) but no OS-level
push. The rest of this doc is what turns the push on.

## What's already done

**Backend** — `backend/app/services/push/`:
- `device_tokens` table (`000030_device_tokens.sql`) — FCM tokens per profile
- `PUT`/`DELETE /api/v1/device-tokens` — the app registers/deregisters its token
- `push_to_member(workspace_id, member_id, …)` — resolves the member's devices and sends via FCM HTTP v1. **No-ops silently** when `FCM_PROJECT_ID` / `FCM_SERVICE_ACCOUNT_JSON` are unset.
- `LeadService.assign_lead` fires the app-path push (skips self-assignment; skips entirely once `INTERNAL_WEBHOOK_SECRET` is set)
- `POST /internal/push/notification` — target for a Supabase Database Webhook, so an assignment made from the **Admin panel** (`UPDATE leads` direct, no FastAPI) also pushes

**Mobile** — `mobile/lib/features/push/`:
- `PushRegistrar` — booted at app start; registers on login, deregisters on logout, re-registers on token refresh
- Wired against `FcmTokenSource`; the live implementation is `NoopFcmTokenSource` (returns `null`, so registration is a no-op)

## Step 1 — Firebase project

1. [console.firebase.google.com](https://console.firebase.google.com) → add a project.
2. Add an **Android app** with package name `com.crmapp.mobile`. Download `google-services.json` → `mobile/android/app/google-services.json`.
3. (iOS later) add an iOS app, download `GoogleService-Info.plist`.

## Step 2 — FlutterFire

```bash
cd mobile
dart pub global activate flutterfire_cli
flutterfire configure --project=<your-firebase-project-id>
```

This generates `mobile/lib/firebase_options.dart` and patches the Gradle files.

Then add the packages (pin exact versions):

```bash
flutter pub add firebase_core firebase_messaging
```

`mobile/lib/main.dart` — initialise before `runApp`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```

## Step 3 — Implement `FirebaseFcmTokenSource`

`mobile/lib/features/push/data/firebase_fcm_token_source.dart`:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import '../domain/fcm_token_source.dart';

class FirebaseFcmTokenSource implements FcmTokenSource {
  final _fm = FirebaseMessaging.instance;

  @override
  Future<String?> getToken() async {
    final settings = await _fm.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
    return _fm.getToken();
  }

  @override
  Stream<String> get onTokenRefresh => _fm.onTokenRefresh;

  @override
  Future<void> deleteToken() => _fm.deleteToken();
}
```

Then in `mobile/lib/features/push/presentation/providers/push_providers.dart` swap the one line:

```dart
final fcmTokenSourceProvider = Provider<FcmTokenSource>((ref) => FirebaseFcmTokenSource());
```

Nothing else in the push feature changes.

## Step 4 — Backend credentials

Firebase console → Project settings → Service accounts → **Generate new private key**. Then in `backend/.env`:

```
FCM_PROJECT_ID=<your-firebase-project-id>
FCM_SERVICE_ACCOUNT_JSON=/secure/path/to/service-account.json
```

`google-auth` is already in `requirements.txt`. Restart the backend — `get_fcm_sender()` now returns a real sender.

## Step 5 (optional) — Admin-panel assignments

The FastAPI push in step 4 only covers assignments made **through the app**. To also push when a manager reassigns from the Admin panel:

1. `backend/.env`: `INTERNAL_WEBHOOK_SECRET=<a long random string>`
2. Supabase dashboard → Database → Webhooks → new webhook:
   - Table: `notifications`, Events: `INSERT`
   - URL: `https://<your-backend>/internal/push/notification`
   - HTTP header: `x-webhook-secret: <the same string>`

Once `INTERNAL_WEBHOOK_SECRET` is set, `LeadService.assign_lead` stops firing its own push (the webhook now owns every assignment push) — so there's never a double notification.

## Testing on a device

The reset must have run first (`device_tokens` needs to exist). Then: log in on the device, check `select * from device_tokens` has a row, assign a lead to that account from another session, confirm the push arrives with the app backgrounded.
