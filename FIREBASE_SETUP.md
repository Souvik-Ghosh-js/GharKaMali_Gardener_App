# Firebase Setup — GKM Gardener App

Push notifications (FCM) are fully wired in the code but stay **disabled until the
Firebase config file is added**. Without it the app builds and runs normally — no crash.

## 1. Android (required)

1. Go to [Firebase Console](https://console.firebase.google.com) → create (or open) the Ghar Ka Mali project.
2. **Add app → Android** with package name (applicationId):

   ```
   com.example.gkm_gardener
   ```

   (Defined in `android/app/build.gradle.kts`. If you change the applicationId before release —
   recommended, e.g. `in.gobt.gkm.gardener` — register that value instead and keep both in sync.)
3. Download **`google-services.json`** and place it at:

   ```
   android/app/google-services.json
   ```
4. Rebuild (`flutter run` / `flutter build apk`). The google-services Gradle plugin is applied
   automatically once the file exists — nothing else to configure.

Do NOT commit `google-services.json` if the repo is public; add it to `.gitignore`.

## 2. iOS (only if we ever ship iOS)

1. Firebase Console → **Add app → iOS** with the bundle id from `ios/Runner.xcodeproj`
   (currently `com.example.gkmGardener`).
2. Download **`GoogleService-Info.plist`** and add it to `ios/Runner/` via Xcode
   (File → Add Files, make sure "Copy items" and the Runner target are checked).
3. Enable the Push Notifications capability + Background Modes → Remote notifications in Xcode,
   and upload the APNs key in Firebase Console → Project Settings → Cloud Messaging.

## 3. Backend

The Node backend sends the pushes and needs a Firebase **service account** key
(see the header of `GharKaMali_Backend/src/services/push.service.js`):

1. Firebase Console → Project Settings → Service Accounts → **Generate New Private Key**.
2. Save it as `firebase-service-account.json` in the backend root (gitignored),
   **or** set the `FIREBASE_SERVICE_ACCOUNT` env var to the JSON string on the server.

## How it works in the app

- `lib/data/services/push_service.dart` — singleton `PushService`:
  - `init()` (called from `main.dart`) initializes Firebase, asks notification permission
    (incl. Android 13 POST_NOTIFICATIONS), creates the `gkm_gardener` "Job Alerts" channel,
    and wires foreground/background/tap handlers. Fails soft if Firebase isn't configured.
  - Login sends the FCM token with `POST /auth/gardener-login`; app launch (when logged in)
    and token refresh call `POST /auth/update-fcm-token`.
  - Tapping a job notification opens the Jobs tab (or `/job/<id>` if the payload ever
    includes a numeric `booking_id`).
