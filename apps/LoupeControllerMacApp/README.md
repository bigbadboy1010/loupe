# LoupeControllerMacApp

Native macOS controller wrapper for Loupe.

Use this target when a Mac should control another Mac. It reuses `LoupeControllerKit` and does not use camera QR scanning. Pairing is done by copying the host pairing token from the LoupeHost console or by opening a text file that contains the token.

## Run

```bash
cd apps/LoupeControllerMacApp
swift run LoupeControllerMacApp
```

## Notes

- Host remains `LoupeHost` on the controlled Mac.
- Controller remains answerer-only; the host is still the only SDP offerer.
- No server redeploy is required.
