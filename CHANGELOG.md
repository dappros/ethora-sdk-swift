# Changelog

All notable changes to this package are documented here. For cross-SDK release notes, see [ethora/RELEASE-NOTES.md](https://github.com/dappros/ethora/blob/main/RELEASE-NOTES.md).

---

## [26.04.08]

- **Fix:** Adaptive idle ping scheduling no longer stops after the first idle window (`pingInFlight` was set without a real ping/pong).
- **Chore:** Stop tracking SwiftPM `xcuserdata` and expand `.gitignore` for Xcode user state.

## [26.03.02]

- **New:** Push notifications support, code split ([`8b20dcd`](https://github.com/dappros/ethora-sdk-swift/commit/8b20dcd))
