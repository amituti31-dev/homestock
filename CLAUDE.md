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

`GeminiService.parseReceiptImage` and `RecipeService.suggestRecipes` both call
`gemini-2.5-flash` directly from the client with Hebrew prompts that demand
JSON-only output, then regex the first `{...}` block out of the response.
Receipt categories must be one of the exact English enum values in
`InventoryCategory` — keep the prompt's category list in sync with that enum.

### Other integrations

- Barcode: `mobile_scanner` → `BarcodeLookupService` (OpenFoodFacts, 6s timeout,
  returns null on any failure — barcode lookup is best-effort).
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
inventory. No receipt scanning, no Gemini, no inventory browsing — that stays on
the phone.

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
`choco install innosetup` on `windows-latest`.

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
to name it.

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
(measured: 6,435 products in ~200 ms).

`refresh()` (weekly, on launch, and via the manual refresh action) downloads
only from Shufersal and **merges** the result into `_index` rather than
replacing it — barcodes from other chains, added separately, survive a
refresh. Adding another chain's *automatic* download means writing another
downloader — the XML schema is mandated and identical — but most chains sit
behind per-chain credentials. Until then, `tool/import_price_file.dart` merges
an already-downloaded price file (plain XML, not gzipped) from any chain into
the same cache: `dart run tool/import_price_file.dart <PriceFull...xml>`.

## Conventions

- RTL is forced in `MaterialApp.builder`; there is no localization layer.
- Firebase project ID and Web API key are in `lib/firebase_config.dart`. The Web
  API key is not a secret — it identifies the project, and access is controlled
  by `receipt_scanner/firestore.rules`.
- Models are deliberately duplicated from the mobile app rather than shared via a
  package. If that duplication starts to hurt, extract a `shared/` Dart package —
  but keep the Firestore field names identical either way.
