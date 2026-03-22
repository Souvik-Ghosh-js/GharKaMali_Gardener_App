# GKM Gardener — Flutter App

Premium Flutter application for Ghar Ka Mali gardeners.

## Features
- OTP-based login (6-digit code)
- Dashboard with availability toggle + today's jobs
- Full jobs list with Today / Assigned / Active / Done filters
- Job detail with live OTP verification, GPS tracking, before/after photo upload
- Earnings screen with fl_chart bar chart, period breakdown, rewards/penalties
- Profile screen with bio, bank details, service zones, smooth edit mode
- Animated skeleton loaders (shimmer)
- Custom animated toast notifications (top-slide with border accent)
- Premium animated bottom nav bar with pill indicator
- Smooth page transitions (slide + fade)
- Pull-to-refresh on all screens
- Full error handling with user-friendly messages

## Brand Colors
- Forest:   #03411A (primary)
- Gold:     #EDCF87 (accent)
- Gold Dark:#D4B96A
- Sage:     #808285
- Earth:    #96794F

## Setup

1. **Install Flutter** (3.x or above)

2. **Clone/unzip** the project

3. **Configure API URL** — edit `lib/data/services/api_service.dart`:
   ```dart
   const String kApiBase = 'https://gkm.gobt.in/api';
   ```

4. **Install dependencies**:
   ```bash
   flutter pub get
   ```

5. **Run**:
   ```bash
   flutter run
   ```

## Project Structure
```
lib/
├── main.dart                          # Entry, routing, app shell
├── data/
│   └── services/
│       ├── api_service.dart           # All API calls (REST)
│       └── auth_provider.dart         # Auth state (ChangeNotifier)
└── presentation/
    ├── theme/
    │   └── app_theme.dart             # Colors, typography, Material theme
    ├── widgets/
    │   ├── common_widgets.dart        # Cards, skeletons, toasts, buttons
    │   └── bottom_nav.dart            # Premium animated bottom nav
    └── screens/
        ├── login_screen.dart          # OTP phone login
        ├── register_screen.dart       # New gardener application
        ├── dashboard_screen.dart      # Home tab
        ├── jobs_screen.dart           # Jobs list tab
        ├── job_detail_screen.dart     # Job execution flow
        ├── earnings_screen.dart       # Earnings + chart tab
        └── profile_screen.dart        # Profile + settings tab
```

## Android Permissions Required
- INTERNET
- ACCESS_FINE_LOCATION (live job tracking)
- CAMERA (job photos)
- READ/WRITE_EXTERNAL_STORAGE (photo upload)

## Notes
- Token is stored in SharedPreferences under `gkm_gardener_token`
- GPS tracking auto-starts when job status is `en_route` / `arrived` / `in_progress`
- Status updates use multipart form (PUT /bookings/status)

Developed by **Gobt**
