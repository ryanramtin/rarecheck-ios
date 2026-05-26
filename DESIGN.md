# Design System: RareCheck
**Project ID:** rarecheck-ios (no Stitch project yet; synthesized from PNG mockups provided by Ryan on 2026-05-25)
**Mockups analyzed:**
- Kid Friendly Mode — 5-screen core flow + notifications + key elements + settings
- Adult Mode v1 (Advanced) — 5-screen core flow + notifications + key elements + settings
- Adult Mode Updated — 5-screen core flow + notifications + key elements + advanced tools + settings (canonical Adult Mode)

## 1. Visual Theme & Atmosphere

RareCheck is a **dual-personality** product wearing one coherent visual identity. Both modes share the same paper-toned background, the same generously rounded geometry, and the same Pokémon-character vocabulary — but the **information density** and **emotional register** swing dramatically between them.

**Kid Friendly Mode** is "Apple Arcade meets Pokémon GO." Big tappable purple buttons, two CTAs per screen, friendly-mascot illustrations doing all the explaining. Backgrounds drift into soft sky-blue gradients on the home screen. Confetti-like sparkle accents punctuate moments of delight. Notifications are illustrated character cards (Pikachu, Squirtle, Charmander, Gengar, Eevee, Meowth) each with one-line celebratory copy. Tone: **warm, encouraging, never punitive**.

**Adult Mode (Advanced)** is "Apple Wallet meets Robinhood." White paper backgrounds, structured stat lists with right-aligned values, segmented controls for Overview/Price/Details, embedded sparkline charts (1M/3M/6M/1Y), and a four-tile "Advanced Tools" row. Pokémon characters are still present in notifications but the copy is business-toned (Price Update, Market Alert, Collection Milestone). Tone: **confident, data-rich, decision-supporting**.

**Density:** Kid Mode is 2–3 elements per screen. Adult Mode is 6–10. Both modes preserve generous vertical breathing room — nothing fights for space, nothing crowds the edge.

**Shape vocabulary:** Generously rounded corners everywhere (24–32 px). Pill-shaped primary CTAs. Soft chip badges for rarities and conditions. Card-on-paper layering rather than overlapping or nested boxes.

**Mascot strategy:** Pokémon characters are first-class UI elements, not decoration. They communicate *what is happening* (Squirtle = analyzing, Gengar = identifying, Charizard = price moved, Eevee = collection milestone). Mascot choice is semantic and consistent across both modes — only the supporting copy changes.

---

## 2. Color Palette & Roles

### Brand & Primary

| Descriptive Name | Hex | Role |
|---|---|---|
| **Sunset Hot Pink** | `#FF4D8D` | Kid Mode brand color. Used for primary CTA buttons ("Scan Card" purple in newer mock, hot pink in earlier mock — purple wins for newer Adult), highlight accents in marketing surfaces, "Extract Skill" pulse states. |
| **Royal Iris Purple** | `#7C5CFA` | Adult Mode primary action color. "Scan Card" CTA, "Add to Collection" button, selected segmented-control tab, active settings toggle thumb. |
| **Confident Pikachu Gold** | `#FFCC2E` | Secondary CTA in Kid Mode ("Add to Collection" yellow button). Accent for star/sparkle moments in both modes. |

### Surface & Background

| Descriptive Name | Hex | Role |
|---|---|---|
| **Cream Paper** | `#FAF7F0` | Default page background in Kid Mode. Warm off-white that signals "kid-safe, soft" without going saturated. |
| **Cool Studio White** | `#FFFFFF` | Default page background in Adult Mode. True white for maximum data legibility. |
| **Sky Wash** | `linear-gradient(180deg, #BDE0FE 0%, #E7F4FF 100%)` | Kid Mode home screen background — pale sky-blue at top fading to near-white. Used only on screens with mascot hero illustration. |
| **Paper Warm** | `#F4EFE6` | Tab-bar inactive background, settings card subdivider tint, "Suggestions" chip background tint. |

### Text & Ink

| Descriptive Name | Hex | Role |
|---|---|---|
| **Deep Charcoal Ink** | `#1A1A22` | Primary text on light surfaces — headlines, body copy, button labels. |
| **Soft Ink** | `#4A4A55` | Secondary body text, supporting copy ("Tap Scan Card to get started"). |
| **Subtle Ink** | `#8A8A95` | Tertiary captions, timestamps, "Just now / 2h ago" relative dates. |
| **Cream on Ink** | `#FFF8EE` | Text on saturated CTAs (button labels on purple/hot-pink). |

### Rarity & Status Chips

| Descriptive Name | Hex | Role |
|---|---|---|
| **Common Slate** | `#9AA5B1` | Common rarity chip (outlined in Adult, filled-pastel in Kid). |
| **Uncommon Mint** | `#5FD3A8` | Uncommon rarity chip. Same hue both modes. |
| **Rare Sapphire** | `#3B82F6` | Rare rarity chip. |
| **Holo Magenta** | `#E84A8E` | Holo Rare rarity chip. |
| **Ultra Coral** | `#FF6B5A` | Ultra Rare rarity chip. |
| **Secret Gold** | `#FFB23E` | Secret Rare rarity chip (Adult Mode only). |

### Condition Grades (Adult Mode only)

| Descriptive Name | Hex | Role |
|---|---|---|
| **Mint Green** | `#34C759` | MT (Mint) condition chip. |
| **Near-Mint Spring** | `#A6E36F` | NM (Near Mint) — most common positive grade. |
| **Light-Play Amber** | `#F4B748` | LP (Light Play). |
| **Moderate-Play Orange** | `#F08A3E` | MP (Moderate Play). |
| **Heavy-Play Rust** | `#D9613A` | HP (Heavy Play). |
| **Damaged Crimson** | `#C44545` | DMG (Damaged). |

### Market Movement (Adult Mode dashboard)

| Descriptive Name | Hex | Role |
|---|---|---|
| **Rising Green** | `#1FB37D` | Positive price/trend deltas ("▲ 22.4%", "+12% in 7 days"). |
| **Falling Red** | `#E33D3D` | Negative price/trend deltas ("▼ 12.6%"). |

### Suggestion Tile Pastels (Kid Mode + marketing surfaces)

| Descriptive Name | Hex | Role |
|---|---|---|
| Tile Coral | `#FFE2D9` | "PowerPoint Executive Update" / playful warmth |
| Tile Mint | `#D7F3E1` | "Writing Clear Acceptance Criteria" / positive go |
| Tile Amber | `#FFEBC2` | "App Security Review" / caution but friendly |
| Tile Lime | `#E5F3C2` | "Architecture Decision Record" / fresh signal |
| Tile Lilac | `#E7DAFB` | "Code Review Checklist" / thoughtful |

---

## 3. Typography Rules

**Font family:** SF Pro Rounded (system) for the iOS app — the rounded variant pairs perfectly with the generous corner radii and the kid-friendly mascot vocabulary while remaining credible in Adult Mode. Fallback: SF Pro. Weights used: 400 (Regular), 500 (Medium), 600 (Semibold), 700 (Bold), 800 (Heavy/Black for hero numbers).

**Display headline ("Cast any video into a skill file" / "RareCheck"):** SF Pro Rounded, Bold (700), 48–60 pt on hero surfaces, tight tracking (-0.02 em), 1.05 line-height. Headline-bold but never shouty.

**Section headline ("Estimated Value (Raw)", "Recent Comps"):** SF Pro Rounded, Semibold (600), 17–20 pt, default tracking, 1.2 line-height. Often paired with a "See All" affordance right-aligned in the same row.

**Hero number ("$120", "$18,642", "$1,120"):** SF Pro Rounded, Heavy (800), 40–56 pt. Tabular figures so digits don't reflow when the value changes. Currency symbol same weight, half-step smaller.

**Body copy:** SF Pro Rounded, Regular (400), 15–16 pt, 1.45 line-height. Used for descriptions, settings labels, and supporting copy.

**Button label:** SF Pro Rounded, Semibold (600), 16–17 pt, centered. Cream-on-Ink color on saturated CTAs.

**Caption / metadata:** SF Pro Rounded, Medium (500), 12–13 pt, Subtle Ink color, often uppercased with `+0.06em` letter-spacing for section labels ("RARITY BADGES", "CONDITION GRADES", "DATA & PRIVACY").

**Tabular figures:** Always enable `font-feature-settings: "tnum"` on numeric values (prices, percentages, ratings) so values right-align cleanly in stat lists.

---

## 4. Component Stylings

### Buttons

- **Primary CTA (Adult Mode):** Royal Iris Purple `#7C5CFA` fill, Cream on Ink label, 16–18 pt, **pill shape** (fully rounded, `cornerRadius = height / 2`), 56 pt height, full-width within a 16 pt horizontal margin. Whisper-soft shadow (`y: 4, blur: 12, color: rgba(124,92,250,0.20)`).
- **Primary CTA (Kid Mode):** Same shape and shadow, but Sunset Hot Pink `#FF4D8D` fill. Larger touch target (60 pt height) for kid fingers.
- **Secondary CTA (yellow, Kid Mode):** Confident Pikachu Gold `#FFCC2E` fill, Deep Charcoal Ink label. Same pill shape and dimensions. Used for "Add to Collection."
- **Tertiary / ghost button ("View Sales", "More Details"):** White fill, Royal Iris Purple stroke (1.5 pt), Royal Iris Purple label. Same pill shape.
- **Icon button (header back-arrow, share, heart-favorite, flash, gallery):** No fill, 24 pt icon, 44×44 pt tappable region. Deep Charcoal Ink color.

### Cards / Containers

- **Standard card:** Cool Studio White fill in Adult Mode, Cream Paper fill in Kid Mode. **Generously rounded corners** (24–32 px). Whisper-soft diffused shadow (`y: 2, blur: 16, color: rgba(0,0,0,0.04)`) so cards barely lift off the paper background — premium without being heavy.
- **Card stack on home screen (Watchlist, Recent Scans, Market Movers, Settings sections):** Each row inside the card is separated by a 1 pt Subtle Ink hairline at `opacity: 0.08`. Generous internal padding (16–20 pt). Right-aligned values use tabular figures.
- **Mascot card (Kid notifications):** Slightly more rounded (28 px) than standard. Pastel background tint matching the mascot's species (Charizard → warm coral, Pikachu → soft amber, Squirtle → pale blue, Gengar → light lilac, Eevee → cream, Meowth → cream). Character illustration anchors the left, copy stacks right.
- **Settings group container:** Cool Studio White fill, 16 px corner radius (subtler than other cards because it's chrome, not content), 12 pt vertical padding per row.

### Inputs / Forms

- **Text input ("Paste URL", "Email"):** No fill, 1.5 pt Subtle Ink stroke, 12 pt corner radius, 16 pt internal padding, Deep Charcoal Ink text. On focus the stroke shifts to Royal Iris Purple at full opacity. (Adapt from sibling Vid2Skill `field` style.)
- **Toggle / switch:** Standard iOS UISwitch styled with Royal Iris Purple ON-state tint (Adult Mode) or Sunset Hot Pink (Kid Mode). Off-state is Subtle Ink at 30% opacity.
- **Segmented control (Overview / Price / Details):** Rounded pill background `#F4EFE6` Paper Warm. Selected segment fills with Royal Iris Purple `#7C5CFA`, label flips to Cream on Ink. Unselected segments stay transparent with Soft Ink labels.
- **Camera framing brackets:** Four white corner brackets (3 pt stroke, 24 pt arm length), centered on a 3:4 aspect window. White at 100% opacity over the live preview. No darkening of out-of-frame area in Kid Mode (keeps it cheerful); subtle 30% black scrim outside the frame in Adult Mode (improves card legibility for the user's framing).

### Rarity / Condition / Status Chips

- **Rarity chip (Kid Mode):** Filled pastel of the rarity color (e.g., Holo Magenta at 18% opacity background, Holo Magenta text at 100%). 12 px corner radius. Star icon on the left, label centered, 13 pt Semibold.
- **Rarity chip (Adult Mode):** Outlined (1.5 pt stroke of the rarity color), transparent fill, same color text. 8 px corner radius (slightly squarer reads more "data-table"). No leading icon.
- **Condition chip (Adult Mode only):** Filled solid of the condition color, Deep Charcoal Ink text, 12 px corner radius, displayed in a horizontal-scrolling row labeled "CONDITION GRADES."
- **Numeric badge ("8.5 / 10", "$120"):** Tabular figures, Semibold weight, right-aligned in stat lists.

### Bottom Navigation

- **Kid Mode tab bar:** 3 tabs — Scan / Collection / Profile. Icons 28 pt, label 11 pt. Active state: Sunset Hot Pink icon + label. Inactive: Subtle Ink.
- **Adult Mode tab bar:** 5 tabs — Home / Search / Collection / Insights / More. Icons 22 pt, label 10 pt. Active state: Royal Iris Purple icon + label. Inactive: Subtle Ink.
- **Background:** Cool Studio White with a 1 pt Subtle Ink hairline at the top edge (`opacity: 0.08`). No shadow.

### Sparkline / Mini-chart (Adult Mode)

- **Stroke:** 2 pt, Rising Green `#1FB37D` when trend is positive, Falling Red `#E33D3D` when negative.
- **Fill (area under line):** Same hue at 12% opacity, fading to 0% at the baseline.
- **Time selector pill (1M / 3M / 6M / 1Y):** Segmented control variant, but each segment is a small individual pill rather than a continuous track. Selected pill: Royal Iris Purple fill, Cream on Ink label.
- **Embedded in card** with the chart vertically centered between a top stat row (current value + delta) and a bottom date axis.

---

## 5. Layout Principles

**Outer margin:** 16 pt horizontal on every screen. Hero illustrations may bleed to the safe-area edge but copy and CTAs respect the margin.

**Vertical rhythm:** 24 pt between distinct cards on a stacked screen. 16 pt between rows within a card. 8 pt between an item and its supporting caption.

**Hero proportions (Kid Mode):** Mascot illustration occupies roughly the top 40% of the screen on the home. Headline copy below in 24% of remaining height. Two stacked CTAs in the next 24%. Tab bar in the final 12%.

**Hero proportions (Adult Mode):** Top status bar + nav (10%), greeting headline (8%), primary purple Scan Card CTA (10%), secondary buttons Upload Photo + My Collection stacked (16%), Market Trends prompt card (10%), tab bar (8%). Remaining whitespace breathes; nothing is forced to fill it.

**Information density (Adult Mode value screen):** Large hero number stays in the top third. Stat list (4–6 rows: Estimated Value, Market Range, Graded Value, Condition Estimate, Recent Comps, Pop Report) fills the middle. CTAs anchor the bottom safe area. Anything that doesn't fit reveals via a "See All" affordance or a tap into the Insights tab.

**Whitespace strategy:** Generous. The mockups consistently leave 24–32 pt of empty space below the last interactive element before the tab bar. Never edge-to-edge text. Never adjacent cards touching.

**Alignment:** Left-align all body text. Right-align all numeric values in stat lists (tabular figures). Center primary CTAs. Mascot illustrations are usually horizontally centered or left-aligned with copy on the right.

**Safe-area handling:** Respect the iPhone notch / Dynamic Island region — no critical content within 8 pt of the top safe area inset. Bottom safe area always has the tab bar (44 pt) plus 8 pt of breathing room.

**Mode toggle visibility:** The Settings screen always shows BOTH the Kid Friendly Mode toggle and the Adult Mode toggle, with a hairline separator between them. Whichever mode is active has its corresponding toggle in the ON state — they're never both ON, never both OFF.

---

## 6. Iconography & Mascot Vocabulary

**Icon family:** SF Symbols (rounded variants where available). 22–28 pt nominal size. Strokeable variants preferred over filled in tab bars; filled accepted in cards for emphasis.

**Mascot ↔ event mapping (canonical, used across modes):**

| Pokémon | Event semantic | Kid Mode copy | Adult Mode copy |
|---|---|---|---|
| **Pikachu** | Positive identification / personal best | "Great Scan!" "We got a clear look at your card!" | "New Best Card! That's your new highest value card in your collection!" |
| **Squirtle** | In-progress / patience | "Almost There! Just a few more seconds…" | (Used during analyze loop, no notification fires) |
| **Charmander** | Rare-find delight | "Cool Find! This card is really awesome!" | (Reserved for upcoming rare-pull notification) |
| **Charizard** | Price moved up | "Price Update! This card's value changed a little." | "Price Update — Charizard Base Set 4/102 is trending up +12% in the last 7 days." |
| **Gengar** | Market signal / analysis | (Analyzing screen mascot) | "Market Alert — Scarce cards from Base Set are moving fast right now." |
| **Eevee** | Collection milestone | "Added! Your card was added to your collection." | "Collection Milestone — You've scanned 100 cards! Awesome work!" |
| **Mewtwo** | Market intelligence | (Reserved) | "Market Alert — Power signal from Base Set inventory." |
| **Meowth** | Friendly error / retry | "Oops! We couldn't read that card. Try again with a clear photo!" | "Scan Failed — We couldn't get a clear read. Try again in better lighting." |

Mascot illustrations should be **flat vector** style, not photoreal or 3D. Borrow the existing official Pokémon TCG illustration energy (line-art on flat-color fills) but adjust character size so they fit naturally in a 64–80 pt card thumbnail.

---

## 7. Animation & Motion

**Tap feedback:** Light haptic on every primary CTA. Visual: 0.97 scale-down on press, snap back to 1.0 on release (spring, 200 ms).

**Loading / analyzing:** Subtle rotation on the Squirtle/Gengar mascot (Kid/Adult respectively) at 8 RPM, plus the checklist items animate from empty → spinner → green check as each pipeline stage completes. The progress ring (Adult Mode) fills smoothly from 0% to 100% over the actual job duration, not faked.

**Card identified reveal:** The card image scales up from 0.92 → 1.0 with a soft spring (300 ms) while a one-shot sparkle confetti emits around the card edges (Kid Mode only — Adult Mode gets a brief gold-glow border pulse instead).

**Notification entry:** Slide in from the top safe area, settle with a 250 ms spring, auto-dismiss after 4 seconds unless tapped.

**Mode toggle transition:** When the user flips Kid Friendly Mode on/off in Settings, the entire app reloads to the new shell with a 220 ms cross-fade. Not a sliding transition — a clean fade so the change feels like "changing modes" rather than "changing screens."

---

## 8. Open Design Questions

1. **Asset source for Pokémon characters:** Licensed Pokémon TCG illustrations are copyrighted; using them at scale invites App Store rejection or DMCA. Decide: commission original "RareCheck mascot squad" inspired-by characters, or use generic-named cute critters in similar archetypes (electric mouse, water turtle, fire lizard, ghost, etc.).
2. **Dark mode:** Settings shows a "Display Mode → Light" entry, implying Dark is planned. Adult Mode dark variant is straightforward (`#1A1A22` background, invert text). Kid Mode dark is awkward — Sky Wash gradient becomes night-sky? Defer to v1.1.
3. **Currency:** Settings shows "USD ($)" — multi-currency support implied but Pokémon TCG API returns USD only. v1 ships USD-only; surface "Currency" setting as informational with a "Coming soon" disclosure on tap.
4. **Confetti library:** Use SwiftUI native particle animations (iOS 17+) for sparkle effects rather than a third-party library, since RareCheck is iOS 17+ already.
