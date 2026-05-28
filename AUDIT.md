# Poké Rare Check Tech-Director Audit — 2026-05-25

> Read before touching code. Compares the scaffolded scaffold (commits `08057f5` iOS / `00f14a1` api) against the dual-mode mockups + `DESIGN.md`.

## Scope of audit

- Cloned both repos to `Desktop/Development Projects/rarecheck-ios` and `Desktop/Development Projects/rarecheck-api`.
- Read every top-level Swift file (17) and every top-level api file (`src/`).
- Did NOT run `xcodegen generate` or boot the api yet — that's the next concrete step.

## What's already real

### iOS (rarecheck-ios)

| Module | Files | State |
|---|---|---|
| **Scanner** | CameraView, CameraViewModel, CardDetector, OCRService | Real AVFoundation + Vision wiring. Card rectangle detection + OCR pipeline scaffolded. |
| **Matching** | PHashMatcher, CardIdentificationService | pHash with Accelerate/vDSP implemented. Service combines OCR+pHash with 0.6/0.4 weight. |
| **Networking** | APIClient, CardModels | URLSession client, Codable models. Base URL via env var or default. |
| **Cards** | CardDetailView, PriceHistoryChart | SwiftUI views exist. PriceHistoryChart uses SwiftUI Charts (iOS 16+). |
| **Collection** | CollectionView, CollectionViewModel | CoreData-backed grid. |
| **Paywall** | PaywallView, SubscriptionManager | RevenueCat integration scaffolded; entitlement ID `"pro"`. |
| **CoreData** | PersistenceController | `.xcdatamodeld` referenced. |
| **App** | RareCheckApp.swift, ContentView | Entry point + 3-tab nav (Scan/Collection/Settings). |

### Backend (rarecheck-api)

| Module | State |
|---|---|
| `src/index.ts` | Full Express bootstrap with helmet/cors/compression/rate-limiting + health check. |
| `routes/cards.ts` | `POST /api/cards/identify` w/ Joi validation, base64 image up to 5MB, OCR hints from iOS, audit logging. `GET /api/cards/:id` present. |
| `routes/prices.ts` | Pricing endpoints. |
| `services/identificationService.ts` | Matching service (server-side fallback). |
| `services/pokemonTCGService.ts` | pokemontcg.io wrapper. |
| `services/pricingService.ts` | Price aggregation. |
| `jobs/priceCacheJob.ts` | node-cron scheduled price cache refresh. |
| `middleware/` | auth, auditLog, rateLimiter. |
| `db/` | client + migrate + (presumably) schema. |
| `railway.toml` | Railway deploy config present. |

**Verdict:** This is a serious scaffold, not a stub. The previous agent (Codex, judging by style) built a credible v0.

---

## Gaps between scaffold and mockups

### 1. Single-mode app, mockups demand dual-mode

`ContentView.swift:7` defines a 3-tab nav (Scan/Collection/Settings). Mockups require:

- **Kid Mode:** Scan / Collection / Profile (3 tabs, but Profile is not Settings)
- **Adult Mode:** Home / Search / Collection / Insights / More (5 tabs)

Plus a Kid Mode home screen with mascot hero + "Scan Card / My Collection" big buttons (not a tab bar's Scan-by-default).

**Required work:**
- `AppMode` enum (`.kid | .adult`) persisted in `@AppStorage`.
- Root view dispatches to `KidRootView` or `AdultRootView` based on mode.
- Settings exposes mode toggle pair, per `DESIGN.md` §4 → Mode toggle visibility.

**Impact:** ~1 day of UI work, no new dependencies. Scanner/Matching/Networking/CoreData/Paywall stay shared.

### 2. No Home screen / dashboard

Mockups' Adult home is a dashboard (greeting + Scan CTA + Upload Photo + My Collection card + Market Trends prompt). Scaffold's app starts on the camera. **No HomeView exists.**

**Required work:** `HomeView` (Adult) + `KidHomeView` (Kid) — both stack within the new dual-root.

### 3. No Insights / Market Trends tab

Adult Mode bottom nav has "Insights" as the 4th tab — mockup shows Portfolio Value chart, Watchlist, Market Movers (Rising/Falling), Recent Scans. **None of this exists in scaffold.**

**Required work:** Insights tab with sub-cards. Data source: backend needs to expose `/api/users/me/portfolio`, `/api/users/me/watchlist`, `/api/market/movers`. None of these routes exist yet.

### 4. No Search tab

Adult Mode 2nd tab. Likely a card-name search backed by `/api/cards/search?q=`. Scaffold's `cards.ts` does NOT have a search endpoint.

### 5. No "Add to Watchlist" or Price Alerts

Watchlist concept is in the mockup but not modeled in CoreData or backend. Same for Price Alerts.

### 6. Notifications system not implemented

Both mockups show character-led notification cards (Pikachu/Charizard/Mewtwo/Eevee/etc.). No push or in-app notification scaffold exists.

**Required work:**
- iOS: APNs registration, `UNUserNotificationCenter` permission flow, in-app `NotificationCenter` view.
- Backend: push token registration endpoint, scheduled job to compute "Price Update / Market Alert / Collection Milestone" triggers per user.

### 7. Mascot illustrations

`DESIGN.md` §6 maps 8 Pokémon to event semantics. **No image assets exist for any of them.** Bigger question (`DESIGN.md` §8): Pokémon characters are IP-protected. App Store likely rejects an app that uses them at scale.

**Recommended:** Commission or generate "RareCheck mascot squad" — original cute critters in the same archetype slots (electric mouse, water turtle, fire lizard, ghost, etc.). Cheap option: use SF Symbols (`bolt.circle.fill`, etc.) as placeholders for v1 internal builds, swap to original mascots before TestFlight.

### 8. RevenueCat placeholder key

`RareCheckApp.swift:23` ships with `"appl_REPLACE_WITH_YOUR_REVENUECAT_KEY"`. App will crash on first launch in production. Needs a real RevenueCat account + key + product IDs (`com.appgumbo.rarecheck.pro.monthly`, `com.appgumbo.rarecheck.pro.annual`) in ASC.

### 9. ✅ File-name vs. struct-name mismatch — RESOLVED

Previously: `App/CardSignalApp.swift` contained `struct RareCheckApp: App` — the rename commit (`08057f5`) updated the struct but not the file. Fixed via `git mv` to `App/RareCheckApp.swift` on 2026-05-25. Xcode project is XcodeGen-generated (regenerates from `RareCheck/` source globs), so no project-file edits needed.

### 10. No Compare / Grading Guide screens

Adult Mode's "Advanced Tools" four-tile row (Price Alerts / Grading Guide / Compare / Market Trends) implies four destinations. Scaffold has zero of them. Treat as v1.1.

---

## Risks before TestFlight

| Risk | Severity | Mitigation |
|---|---|---|
| **Pokémon IP** | High — likely App Store rejection or DMCA | Original mascot assets before any external build. |
| **RevenueCat placeholder key** | High — crashes production | Wire real key + create products in ASC before first TestFlight. |
| **No mode-toggle UI** | Medium — half the product is unbuilt | Build dual-root + Settings toggle in week 1. |
| **No Insights / Search tabs** | Medium — Adult Mode bottom nav has dead tabs | v1 scope: ship 3 working tabs (Home/Scan/Collection); stub Search + Insights with "Coming soon" cards rather than crash. |
| **Backend not deployed** | Medium — local-only client can't scan-then-fallback | Deploy `rarecheck-api` to Railway as a checkbox before the iOS app expects it. |
| **Privacy nutrition labels** | High at submission — Apple now blocks submissions without published `appDataUsages` (per `App Portfolio Status.md` 2026-05-17) | Same blocker Vid2Skill/TokenBonfire have. Resolve in ASC manually. |
| **`Development Projects` path-with-space** | Low — `pod install` and some Xcode scripts break | If RareCheck needs CocoaPods, use no-space symlink (`/tmp/rarecheck`) per existing PipelineIQ workaround. Currently RareCheck is SwiftPM-only via XcodeGen → no CocoaPods → fine. |
| **No tests** | Medium — `RareCheckTests/` is a stub dir | Add unit tests for `PHashMatcher`, `CardIdentificationService`, `APIClient` request shapes before any major refactor. |

---

## Recommended build order (week 1)

1. **Validate scaffold runs.** `xcodegen generate`, build for simulator, fix any compile errors, confirm camera permission prompt + scan loop works end-to-end against the production-deployed backend.
2. **Deploy `rarecheck-api` to Railway.** Provision project, set env vars (PG URL, Pokémon TCG API key, JWT secret), `railway up`, confirm `/health` returns 200.
3. **Rename file + struct + bundle ID** to RareCheck consistency. `RareCheckApp.swift` → `RareCheckApp.swift`.
4. **Add `AppMode` + dual-root.** Implement `KidRootView` and `AdultRootView` (Kid: 3-tab bar, Adult: 5-tab bar). Settings screen shows both toggles.
5. **Wire RevenueCat properly.** Create products in ASC + RevenueCat dashboard, replace placeholder key, test purchase flow with sandbox account.
6. **Build Adult Home (dashboard).** Greeting, Scan Card CTA, Upload Photo, My Collection card with count, Market Trends prompt. Stub data initially.
7. **Build Kid Home.** Mascot hero, two big buttons, sky-wash background.
8. **Stub Search + Insights tabs** with "Coming soon" placeholder cards.
9. **Commission / generate original mascot assets** before any external build (TestFlight or App Store).
10. **Privacy nutrition labels** in ASC.

Weeks 2+: Notifications, Watchlist, Price Alerts, Compare, Grading Guide, Market Movers.

---

## File-by-file changes ahead (cheat sheet)

| File | Change |
|---|---|
| `RareCheck/App/RareCheckApp.swift` → `RareCheckApp.swift` | Rename file. Replace placeholder RevenueCat key with `Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY")` reading from Info.plist (committed via `.xcconfig`, not source). |
| `RareCheck/App/ContentView.swift` | Replace 3-tab TabView with `AppMode` dispatch. New `KidRootView` and `AdultRootView`. |
| **NEW** `RareCheck/App/AppMode.swift` | `enum AppMode: String, Codable { case kid, adult }` + `@AppStorage("appMode")` wrapper. |
| **NEW** `RareCheck/App/KidRootView.swift` | 3-tab bar (Scan/Collection/Profile). |
| **NEW** `RareCheck/App/AdultRootView.swift` | 5-tab bar (Home/Search/Collection/Insights/More). |
| **NEW** `RareCheck/Home/KidHomeView.swift` | Mascot hero + two CTAs + sky-wash bg. |
| **NEW** `RareCheck/Home/AdultHomeView.swift` | Dashboard per Adult Mode mockup. |
| `RareCheck/App/ContentView.swift::SettingsView` → split | Move to `Settings/AdultSettingsView.swift` + create `Settings/KidSettingsView.swift`. |
| **NEW** `RareCheck/Search/AdultSearchView.swift` | Stub "Coming soon" v1. |
| **NEW** `RareCheck/Insights/AdultInsightsView.swift` | Stub "Coming soon" v1. |
| `RareCheck/Networking/APIClient.swift` | Add base URL env handling: prod Railway URL via `Bundle` Info.plist `API_BASE_URL`. |
| `rarecheck-api/src/routes/*.ts` | NEW v1.1: `users/me/watchlist`, `users/me/portfolio`, `market/movers`, `cards/search`. |
| `rarecheck-ios/RareCheck/Resources/Assets.xcassets` | Mascot images (PLACEHOLDER → REAL before external build). |

---

## Confidence

- The scaffold is **trustworthy**: real implementations of the hard parts (Vision OCR, pHash matching, identification confidence weighting, RevenueCat, CoreData persistence).
- The **gap to the mockups is UI shell + new endpoints**, not algorithm work.
- v1 ship target is plausible in 1.5–2 weeks of focused work, gated by mascot asset creation and privacy labels (both Ryan-side, not code).
