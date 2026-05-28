# Poké Rare Check — Pokémon Card Scanner & Pricing

[![iOS](https://img.shields.io/badge/iOS-17.0%2B-blue)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.10-orange)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-26.4-blue)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Point your iPhone camera at any Pokémon card. Get the price instantly.

## Features

| Feature | Free | Pro ($4.99/mo · $19.99/yr) |
|---|---|---|
| Camera scan + identify card | ✅ | ✅ |
| View current market price | ✅ | ✅ |
| Save to collection | ✅ (20 cards) | ✅ Unlimited |
| 30-day price history chart | ❌ | ✅ |
| Bulk scan mode | ❌ | ✅ |
| CSV collection export | ❌ | ✅ |

## Architecture

```
iPhone Camera (AVFoundation)
    ↓
Card detection (VNDetectRectanglesRequest + perspective crop)
    ↓
┌─────────────────────────────────────────┐
│  Parallel identification pipeline        │
│                                         │
│  OCR (VNRecognizeTextRequest)           │
│  → name, set code, collector #          │
│                                         │
│  pHash image matching (Accelerate/vDSP) │
│  → visual similarity score              │
└──────────────┬──────────────────────────┘
               ↓  confidence = 0.6·OCR + 0.4·pHash
    confidence ≥ 70%? → resolve locally
    confidence < 70%? → POST /api/cards/identify
               ↓
    CardDetailView (price, rarity, set)
    PriceHistoryChart (SwiftUI Charts, 30d, Pro only)
               ↓
    CoreData collection (free: 20, Pro: unlimited)
```

## Tech Stack

- **Language:** Swift 5.10
- **UI:** SwiftUI
- **Camera:** AVFoundation
- **OCR:** Vision framework (`VNRecognizeTextRequest`)
- **Image matching:** Perceptual hash via Accelerate/vDSP
- **Persistence:** CoreData
- **Charts:** SwiftUI Charts (iOS 16+)
- **Subscriptions:** RevenueCat
- **Minimum deployment:** iOS 17.0

## Project Structure

```
RareCheck/
├── App/                    # Entry point, TabView
├── Scanner/                # Camera, OCR, card detector
├── Matching/               # pHash matcher, identification service
├── Cards/                  # Card detail view, price history chart
├── Collection/             # CoreData-backed collection grid+list
├── Paywall/                # RevenueCat paywall + subscription manager
├── Networking/             # URLSession API client, models
├── CoreData/               # .xcdatamodeld, PersistenceController
└── Resources/              # Info.plist, Assets
```

## Getting Started

### Prerequisites
- Xcode 26+ (iOS 17 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

### Setup

```bash
git clone https://github.com/ryanramtin/rarecheck-ios.git
cd rarecheck-ios

# Generate Xcode project
xcodegen generate

# Open in Xcode
open RareCheck.xcodeproj
```

### RevenueCat Configuration

1. Create a RevenueCat account at [revenuecat.com](https://www.revenuecat.com)
2. Add your API key in `RareCheckApp.swift`:
   ```swift
   Purchases.configure(withAPIKey: "YOUR_KEY_HERE")
   ```
3. Create products in App Store Connect:
   - Monthly: `com.appgumbo.rarecheck.pro.monthly` ($4.99/mo)
   - Annual: `com.appgumbo.rarecheck.pro.annual` ($19.99/yr)
4. Set entitlement ID `"pro"` in RevenueCat dashboard

### Backend

See [rarecheck-api](https://github.com/ryanramtin/rarecheck-api) for the Node.js/Express/PostgreSQL backend.

Set your API base URL in `APIClient.swift` or via the `API_BASE_URL` environment variable.

## Building

```bash
xcodebuild \
  -project RareCheck.xcodeproj \
  -scheme RareCheck \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  build
```

## Security Notes

- JWT stored in iOS Keychain (never UserDefaults)
- No sensitive card data logged in production
- Base64 images compressed to <500KB before transmission
- All user collection data scoped by userId (IDOR-safe)

## License

MIT
