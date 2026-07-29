# Manual QA: Career and Online

Smoke checks:

- Launch app on 320x568, 360x640, and 390x844.
- Confirm first screen shows Career and Online Duel as the only primary mode cards.
- Confirm there is no bottom navigation, Play tab, Compete tab, tournament hub, country hub, clan hub, replay entry, or chat entry.
- Open Career and start a puzzle.
- Open Online Duel and verify fee/pot changes when difficulty changes.
- With low balance, verify the Coin Store prompt uses the selected difficulty fee.
- Open Coin Store and verify Coin products are separate from Remove ads.
- Buy/restore `no_ads` in a sandbox account and confirm rewarded ad offers disappear.
- Confirm offline Career still works when Firebase/social backend is unavailable.
- Test light, dark, high contrast, text scale 1.3, and RTL layout.

Production-only checks:

- Verify Google Play `no_ads` is not consumed.
- Verify App Store `no_ads` survives restore.
- Verify wallet response includes `entitlements.noAds`.
- Verify backend rejects replayed purchase tokens across players.

