# HomeStock

Two Flutter apps over one shared Firebase project, for managing a household's
home inventory. All user-facing text is **Hebrew (RTL)**.

| Folder | Platform | Role |
| --- | --- | --- |
| `receipt_scanner/` | Android | The full app: receipt scanning, inventory, shopping list, recipes, notifications |
| `desktop_scanner/` | Windows | Barcode scanning only — a fast intake station that writes into the same inventory |

Both write to `households/{id}/items` in Firebase project `home-inventory-32dd1`,
so a product scanned on the desktop appears on the phone immediately. The
`InventoryItem` field names and the `InventoryCategory` / `StorageLocation` enum
*names* are the contract between them — changing one side requires the other.

`InventoryCategory` has 15 values: 5 non-food (`medicine`, `clothingHome`,
`cosmetics`, `tools`, `hobby`) plus food split into `dairy`, `meatFish`,
`vegetablesFruits`, `snacks`, `breadBakery`, `beverages`, `cannedDry`,
`frozen`, `spicesSauces` — with `food` itself kept as a catch-all ("מזון אחר")
for groceries that don't fit a subcategory. `food` is also `fromName()`'s
fallback for an unrecognized value, so it stays the safe default rather than
being removed. There's no single source of truth for the category list: the
enum, both apps' classifiers, and both of `GeminiService`'s prompts (receipt
parsing and product classification, each listing all 15 values by hand) all
need updating together when a category is added or renamed.

Every new item — from a receipt, or a barcode scan on either app — gets
classified by `GeminiService.classifyProduct` (a short "what category is
this product name" prompt, distinct from the receipt-parsing one) *first*,
falling back to the local, instant `CategoryClassifier` (duplicated in both
apps — see their Architecture sections) whenever Gemini is unavailable, over
quota, or times out (6s) — a scan must never hang waiting on the network.
`CategoryClassifier` picks between the food subcategories by keyword; its
map order is a priority order, not just readability — sauces/spices are
checked before produce/snack keywords (a jarred "רוטב עגבניות" shouldn't
land in vegetablesFruits just because it names tomatoes), and `beverages`
and `frozen` before `vegetablesFruits`/`snacks` because "מיץ תפוזים" (orange
juice) and "גלידת שוקולד" (chocolate ice cream) contain a fruit/snack
keyword but belong to the more specific category.

Public repo at `github.com/amituti31-dev/homestock`. Nothing secret is tracked
(see `.gitignore` at root) — the Firebase Web API key in
`desktop_scanner/lib/firebase_config.dart` is not a secret; access is gated by
`receipt_scanner/firestore.rules`, not by hiding the key.

---

# receipt_scanner (Android)

## Commands

```bash
cd receipt_scanner
flutter pub get
flutter run                 # Android device/emulator
flutter analyze
flutter build apk --release
dart run flutter_launcher_icons   # regenerate app icons after changing assets/icon/
```

## Architecture

- `lib/main.dart` — `HomeStockApp`. Boots dotenv → Firebase → `NotificationService`,
  then `AuthService().ensureHousehold()` resolves the household ID before rendering
  `HomeShell`. Seed color `#4CAF50`, Material 3.
- `lib/screens/home_shell.dart` — 4-tab `IndexedStack`: בית / מלאי / קניות / הגדרות.
  Receipt scan, barcode scan, add-edit, item confirmation and recipes are pushed on top.
- `lib/services/` — one class per concern, no DI framework; screens instantiate directly.
- `lib/models/` — plain Dart with `fromFirestore` / `toFirestore` / `fromJson`.

### Households are the unit of data

Everything is scoped to a household, not a user. `FirestoreService` is constructed
with a `householdId` and reads/writes `households/{id}/items` and
`households/{id}/shoppingList`. `users/{uid}.householdId` maps a user to theirs.

Auth starts **anonymous** — a household is created on first launch. Google sign-in
*links* to the anonymous account to preserve that household, unless the Google
account already has its own Firebase user, in which case its household takes over.
Sharing a home = joining another household by its ID (`joinHousehold`), which makes
the household doc ID an invite code.

When the household changes, `main.dart` re-runs `ensureHousehold()` and rebuilds
`HomeShell` with a new `ValueKey` so all streams re-subscribe.

### Gemini

`GeminiService.parseReceiptImage`, `RecipeService.suggestRecipes` and
`GeminiService.classifyProduct` all call `gemini-2.5-flash` directly from the
client with Hebrew prompts. The first two demand JSON-only output and regex
the first `{...}` block out of the response; `classifyProduct` asks for a
single bare category value instead (used by the barcode scan flow, see
below) and is wrapped in a 6s timeout since — unlike a receipt photo, which
already has a loading spinner — it sits in a scan loop that should feel
instant. Categories returned by any of these must be one of the exact
English enum values in `InventoryCategory` — keep each prompt's category
list in sync with that enum.

### Running out feeds the shopping list

Whenever a quantity drop brings an item to exactly 0 — the inventory list's
+/- buttons, the barcode sheet's "הורד 1", or consume-mode scanning on either
app — it's added to `households/{id}/shoppingList` via
`FirestoreService.addLowStockToShoppingList` (mobile) /
`FirestoreService.addToShoppingList` (desktop, a trimmed REST equivalent with
no `ShoppingListItem` model of its own), marked `autoGenerated: true` and
linked back via `inventoryItemId`. This is the same mechanism the existing
manual "מלאי נמוך" button on the home screen uses for the `minQuantity`
threshold — reaching zero is just treated as the most extreme case of low
stock, not a separate feature. Both call sites dedup against any unchecked
auto-generated entry already linked to that item, so scanning something to
zero twice doesn't double the list.

Consume mode's "last unit" deletes the inventory document rather than leaving
it at a lingering zero (see below) — `markShoppingListItemBought` accounts for
this: if the linked item no longer exists when the shopping-list entry is
checked off, it creates a fresh inventory item instead of trying to update a
document that's gone.

### Other integrations

- Barcode: `mobile_scanner` → `ProductResolver` (local price index first, then
  OpenFoodFacts — see desktop_scanner's "Product lookup" section; both
  services and desktop's bundled seed assets are duplicated byte-for-byte
  into this app). Camera misses used to be common for Israeli products OFF
  has never heard of but the local index does — losing the index was a real
  bug, not just an OFF gap. `BarcodeScannerScreen` has the same add/consume
  mode toggle as the desktop scanner (see below) — consume mode bumps
  quantity down (or deletes at the last unit) directly on detection, no
  sheet, no confirmation. New items get classified by Gemini first,
  `CategoryClassifier` as fallback (see "Gemini" above), rather than always
  defaulting to food. A keyboard icon in the app bar opens a manual-entry
  dialog for a damaged/unscannable barcode — it feeds the same
  `_handleBarcode` the camera detector uses, so a typed barcode goes through
  identical lookup/classify/consume-mode handling.
- Notifications: `flutter_local_notifications` + `timezone`, scheduled per item
  expiry date. Lead days stored in `SharedPreferences` (`expiry_reminder_lead_days`,
  default 3).
- Export: `ExcelExportService` writes an xlsx to temp and hands it to `share_plus`.

## Conventions

- **Hebrew UI strings inline** in widgets — there is no localization layer. Don't
  introduce one unless asked.
- Secrets: `GEMINI_API_KEY` in `receipt_scanner/.env`, loaded via `flutter_dotenv`
  and bundled as an asset. `.env` and `google-services.json` are untracked (see
  root `.gitignore`) — never paste their contents into code, logs, or commits.

### Releases & self-update

`.github/workflows/release-mobile.yml` builds and publishes a GitHub release
on every push to `main` that touches `receipt_scanner/`, tagged `android-vN`
(desktop's workflow already uses plain `vN`, so the two release streams stay
distinguishable in the same repo). The APK is built with
`--build-number=<run number>` to match.

**Release signing must stay stable across builds** — a CI-built APK has to
install as an *update* over a previous one, which Android only allows if both
are signed with the same key. `android/app/build.gradle.kts` reads
`android/key.properties` (untracked) for the release signing config, falling
back to the debug key only when that file is absent (so a fresh clone can
still `flutter run --release`, just not produce an installable-as-update
APK). The actual keystore lives outside the repo, base64-encoded into a
GitHub secret; the workflow decodes it before building. Four repo secrets are
required (Settings > Secrets and variables > Actions):
`GEMINI_API_KEY`, `GOOGLE_SERVICES_JSON_BASE64`, `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`.

`services/update_service.dart` (present in both apps, near-identical) lists
`.../releases` rather than hitting `.../releases/latest`, and picks the
newest release matching its own tag pattern (`vN` or `android-vN`) — with two
release streams in one repo, "latest" could just as easily be the other app's
release. A newer build shows a dismissible `MaterialBanner` linking to the
download; neither app self-replaces its own running binary.

---

# desktop_scanner (Windows)

A single-purpose intake station: a USB barcode scanner types a barcode, the app
looks the product up on Open Food Facts and writes it straight into the shared
inventory. No receipt scanning, no inventory browsing — that stays on the
phone. It does call Gemini now (see Scan flow below), but only a one-line
"classify this product name" prompt, not receipt parsing.

## Commands

```bash
cd desktop_scanner
flutter pub get
flutter run -d windows
flutter test
flutter analyze
flutter build windows --release   # build\windows\x64\runner\Release\

# Installer (run the release build first — ISCC packages its output, it does
# not build anything itself):
"$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe" installer/HomeStockScanner.iss
# → installer\Output\HomeStockScanner-Setup.exe
```

## Packaging

`installer/HomeStockScanner.iss` is the Inno Setup script. The app icon lives at
`windows/runner/resources/app_icon.ico` (generated from the mobile app's
`assets/icon/app_icon.png` — both apps share one logo on purpose), and the exe's
product name / publisher strings are in `windows/runner/Runner.rc`.

The installer deliberately has no `[UninstallDelete]`: the household link and
anonymous credentials live in `%APPDATA%\HomeStock\`, and keeping them means a
reinstall doesn't prompt for the household code again.

### Releases & self-update

`.github/workflows/release-desktop.yml` builds and publishes a GitHub release
on every push to `main` that touches `desktop_scanner/`. The release tag is
just the CI run number (`v1`, `v2`, ...) — not semver — and the exe is built
with `--build-number=<run number>` to match, via `subosito/flutter-action` +
`choco install innosetup` on `windows-latest`. Needs the `GEMINI_API_KEY`
repo secret (the same one `release-mobile.yml` uses) to write `.env` before
building.

`services/update_service.dart` polls
`api.github.com/repos/amituti31-dev/homestock/releases/latest` on launch and
compares its numeric tag against `PackageInfo.buildNumber`. A newer build
shows a dismissible `MaterialBanner` linking to the installer asset — it does
not self-replace the running exe, just opens the download in a browser.
Because the repo is public, this needs no auth token; keep it public or this
breaks (GitHub's release API 404s anonymous requests against private repos).

## Architecture

### No `cloud_firestore` — everything goes over REST

`cloud_firestore` and `firebase_auth` have **no Windows support**, so this app
talks to Firebase directly over HTTP:

- `services/auth_service.dart` — anonymous sign-up via the Identity Toolkit REST
  API, refresh token cached in `SharedPreferences`. The uid must stay stable
  across restarts: the household's `members` list is keyed by uid.
- `services/firestore_service.dart` — reads via `GET` and `:runQuery`, **all
  writes via `documents:commit`**.
- `services/rest_value.dart` — the REST API's typed value format
  (`{"stringValue": …}`). Note `decodeDouble` accepts `integerValue` too:
  Firestore returns whole numbers written as doubles that way.

Writes go through `:commit` rather than `createDocument`/`PATCH` because it is
the only endpoint supporting **field transforms**, the REST equivalents of
`FieldValue.serverTimestamp()` and `FieldValue.increment()`. Both matter here:
the phone and the desktop write to the same documents, so a read-modify-write
increment would silently drop a scan. Don't "simplify" these back into plain
document writes.

Consequences of using `:commit`: document IDs must be generated client-side
(`_autoId`, matching Firestore's 20-char base62 format), and `currentDocument`
preconditions replace the implicit create/update semantics.

### Linking to a household

The security rules gate every item read/write on household membership, so on
first run `SetupScreen` takes the household ID (the invite code from the phone's
settings), calls `joinHousehold`, and stores it in `SharedPreferences`. The rules
permit a non-member to update a household **only** if the result adds them to
`members`, which is why the list is read first and re-sent whole.

### The scanner is a keyboard

It's an HID keyboard-wedge device: it types the digits and presses Enter. There
is no driver, SDK or serial port — just a permanently focused `TextField`
(`_ScannerInput`) with `onSubmitted`. Anything that steals focus breaks scanning,
so `_refocus()` is called after every dialog, tap and completed scan.

### Scan flow

Barcode → already in inventory? bump quantity : resolve the product → create the
item. A miss is **not** an error: the item is still created as 'מוצר לא מזוהה'
so the scanning loop never blocks, and the activity list offers an edit dialog
to name it. A resolved product's name is classified by `GeminiService.classifyProduct`
first, falling back to the local `CategoryClassifier` (keyword matching against
real product-name vocabulary) whenever Gemini is unavailable, over quota, or
past its 6s timeout, so new items land in a real category instead of always
defaulting to food; still editable afterward, it's a guess, not a guarantee.
Both services are duplicated into `receipt_scanner` for its own barcode flow.

A `SegmentedButton` above the scanner input switches between **add mode**
(green tint, the default — the flow above) and **consume mode** (red tint):
scanning bumps the quantity *down* by one instead, or deletes the item once
it's down to the last unit. A barcode not already in the inventory is a no-op
in consume mode, not a create — there's nothing to take off. No confirmation
dialog, unlike the activity list's own remove button: the point of the mode
is a fast scan-to-consume loop, and the tinted background is what stops you
from doing it in the wrong mode by mistake.

### Product lookup: local index first, then Open Food Facts

`ProductResolver` chains two sources, and the order is deliberate:

1. **`ProductIndexService`** — a local barcode→name index built from Israeli
   supermarket price-transparency files. Israeli chains must publish their full
   catalogue: several thousand products per store file, a few hundred KB
   gzipped, Hebrew names, **including non-food** household goods.
   Cached as JSON in the app support dir (`%APPDATA%\HomeStock\HomeStock
   Scanner\product_index.json`).
2. **Open Food Facts** — food only, but the sole source of product *photos*.

So a hit in the index still queries OFF for an image, which is what
`ProductSource.combined` means. Note the Shufersal files leave
`ManufacturerName` empty — the brand is already inside `ItemName` — so
`IndexedProduct.manufacturer` is usually null; other chains do populate it.

`parsePriceFile` uses the streaming `parseEvents` API, not `XmlDocument`: the
files are ~5 MB of XML holding a flat item list, and a full tree is wasted work
(measured: 6,435 products in ~200 ms). It's no longer called at runtime (see
below) but stays around for `tool/generate_price_asset.dart` and its tests.

### Bundled chain seeds, not a live download

`refresh()` used to download live from `prices.shufersal.co.il`, but some
machines fail TLS certificate verification against arbitrary external hosts
(seen in the field against both Shufersal's site and GitHub's, for reasons
outside this app's control — Windows-machine-specific root certificate
issues). So instead, **every chain's price data ships bundled inside the
app**: `assets/{shufersal,yohananof,superpharm,hatzi_hinam}_seed.json`, one
per chain, generated from a price file with `dart run
tool/generate_price_asset.dart <PriceFull...xml> <name>` (writes
`assets/<name>_seed.json`), plus `assets/manual_additions_seed.json` for
barcodes with no chain file at all (see below). `refresh()` just loads and
merges all five via `rootBundle` — no network call, so it behaves identically
on every install
regardless of that machine's certificate store. The trade-off is freshness:
refreshing the data means regenerating the assets and shipping a new release,
not something a running install can do on its own — a fresh machine gets the
full multi-chain index automatically on first launch (`_loadIndex` in
`ScanScreen` treats a never-refreshed index as stale and calls `refresh()`
silently), no setup step required.

Adding another chain means finding its price-transparency feed and running
the generator against it — the XML schema is mandated and identical across
chains, so no new parser is needed, only a new `assets/<name>_seed.json` plus
a line in `pubspec.yaml`'s `flutter.assets`. `tool/import_price_file.dart`
merges an already-downloaded price file directly into the on-disk cache
instead (not a bundled asset) for one-off additions between releases:
`dart run tool/import_price_file.dart <PriceFull...xml>`.
`tool/add_manual_product.dart` and `tool/remove_product.dart` add or remove
one barcode by hand, for cases (like a product OFF has never heard of) no
price file covers — by default against the local cache; `--bundle` instead
writes to `assets/manual_additions_seed.json`, for a one-off addition that
should reach every install once released, not just this machine. It verifies
the JSON round-trips before writing, since a Hebrew name mangled by argument
encoding should fail loudly there, not silently corrupt the file.

## Conventions

- RTL is forced in `MaterialApp.builder`; there is no localization layer.
- Firebase project ID and Web API key are in `lib/firebase_config.dart`. The Web
  API key is not a secret — it identifies the project, and access is controlled
  by `receipt_scanner/firestore.rules`.
- Secrets: `GEMINI_API_KEY` in `desktop_scanner/.env` (same value as
  `receipt_scanner/.env`), loaded via `flutter_dotenv` and bundled as an
  asset — same pattern as the mobile app. `.env` is untracked (see root
  `.gitignore`).
- Models are deliberately duplicated from the mobile app rather than shared via a
  package. If that duplication starts to hurt, extract a `shared/` Dart package —
  but keep the Firestore field names identical either way.
