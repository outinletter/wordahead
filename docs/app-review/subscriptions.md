# WordAhead Plus

- Product: `com.addvalue.wordahead.plus.annual`
- App Store Connect subscription ID: `6824450038`; group: `22492648`.
- Annual auto-renewable subscription, Korea price KRW 29,000. Other storefront prices use Apple's conversion.
- Free: three successful analyses of distinct new YouTube videos per device/day. Failed analyses release reservations; previously analyzed videos, existing captions/words and YouTube playback stay free. Manual text entry remains available.
- StoreKit 2 verified current entitlements determine access; purchase, cancellation, pending approval, transaction updates and explicit purchase restoration are handled. No client premium toggle is trusted.
- Until the StoreKit product is available at least once, analysis stays available to avoid an unpurchasable lock. After catalog activation, cached quota applies if StoreKit temporarily fails.
- Quota is local, not cross-device/account/server enforced. Reinstalling may reset usage; this is not abuse-proof metering.
- No video downloads, decryption or audio extraction. YouTube-app downloads cannot be imported; saved text/words remain offline.
- Player keeps the same WKWebView and restores rate, volume/mute and supported captions font size without seeking or starting playback. YouTube does not publicly expose every caption menu setting; caption language/on-off persistence cannot be guaranteed across a player reload.

## Verification

- `node scripts/check_learning_upgrade.cjs`: rejects editorial dictionary garbage, finds inflected lemmas and persists successful Korean results.
- `node scripts/check_player_settings.mjs`: repeated restoration never seeks/restarts, background transient rate reset is ignored, supported caption font size restores.
- Native quota harness: first three/concurrent reservations, failed analysis release, existing-video access, daily reset and clock rollback pass.
- Mobile browser: short meaning shrinks to about 89 px; long meaning scrolls within 168 px maximum. Caption alignment is exactly two line heights below the reader header.
- Release archive build 24 passed. No TestFlight upload or App Review submission has been made for this change yet.
- App Store Connect: annual product, KRW 29,000 base pricing, availability in all 175 current storefronts, Korean/English product and group localizations, review notes and paywall UI screenshot saved as a draft. Review screenshot uses a catalog fixture of the configured product; it is not proof of a completed transaction.
- Required before release: real device background/foreground YouTube settings check and sandbox purchase/restore/renewal/revocation test. An archive alone does not verify StoreKit purchases.
