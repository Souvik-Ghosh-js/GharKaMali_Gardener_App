# Lottie Animations

Place your Lottie JSON files here. Recommended free animations:

1. **plant_grow.json** — Loading/splash (LottieFiles: search "plant grow")
2. **success.json** — Job completed success state  
3. **location_pin.json** — Live GPS tracking indicator
4. **wallet.json** — Earnings screen hero

Download from: https://lottiefiles.com (free tier)

Usage in Flutter (already configured in pubspec.yaml):
```dart
import 'package:lottie/lottie.dart';

Lottie.asset(
  'assets/lottie/plant_grow.json',
  width: 120, height: 120,
  repeat: true,
)
```

The app uses flutter_animate for micro-animations and transitions.
Lottie is included as a dependency and ready to use once you add JSON files.
