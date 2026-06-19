# Validation

Ausgeführt im korrigierten `loupe-signaling`:

```bash
npm ci --no-audit --no-fund
npm run typecheck
npm run build
npm run test:smoke
HOST=127.0.0.1 PORT=18080 TURN_SECRET=0123456789abcdef0123456789abcdef TURN_HOST=127.0.0.1 npm start
curl -fsS http://127.0.0.1:18080/healthz
```

Ergebnis:

- TypeScript typecheck: bestanden
- Runtime build: bestanden
- Smoke-Test: bestanden
- `npm start` startet `dist/server.js` korrekt
- `/healthz` antwortet erfolgreich

Hinweis:

- Swift-Packages wurden in dieser Linux-Umgebung nicht kompiliert, weil macOS/iOS-Frameworks wie ScreenCaptureKit, CoreGraphics, AppKit/UIKit und die WebRTC-XCFramework-Auflösung dafür eine Apple/Xcode-Umgebung benötigen.
