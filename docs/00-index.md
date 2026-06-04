# Loupe Dokumentation — Index

**Willkommen!** Dieser Index führt dich durch alle Loupe-Dokumente.

---

## 🚀 Für Einsteiger

| Dokument | Zweck |
|----------|-------|
| [Quickstart](../README.md#schnellstart) | TL;DR – In 5 Minuten loslegen |
| [quickstart.md](quickstart.md) | Schritt-für-Schritt Anleitung |
| [build-guide.md](build-guide.md) | Detaillierte Build-Anleitung |

---

## 📖 Referenz

| Dokument | Inhalt |
|----------|--------|
| [architecture.md](architecture.md) | Systemarchitektur, Datenfluss, WebRTC |
| [troubleshooting.md](troubleshooting.md) | Fehlerbehebung, häufige Probleme |
| [iphone-test-acceptance.md](iphone-test-acceptance.md) | E2E Test Kriterien (Pass/Fail) |

---

## 🗺️ Roadmaps

| Dokument | Inhalt |
|----------|--------|
| [mvp-scope.md](mvp-scope.md) | MVP Meilensteine und Status |
| [ui-diagnostics-roadmap.md](ui-diagnostics-roadmap.md) | UI/Diagnostics Entwicklungsplan |
| [product-roadmap.md](product-roadmap.md) | Langfristige Produktvision |

---

## 🏗️ Architektur-Entscheidungen (ADRs)

| Dokument | Thema |
|----------|-------|
| [ADR-001-transport.md](ADR-001-transport.md) | Warum WebRTC statt QUIC? |
| [ADR-002-libwebrtc.md](ADR-002-libwebrtc.md) | Warum Apples libwebrtc? |
| [ADR-003-pairing.md](ADR-003-pairing.md) | QR-Pairing & TOFU Trust Model |

---

## 🔧 Entwickler-Doku

| Dokument | Zweck |
|----------|-------|
| [openclaw-next-prompt.md](openclaw-next-prompt.md) | Exakter OpenClaw Workflow |
| [hardening-changes.md](hardening-changes.md) | Sicherheitshärtung |

---

## 📦 Releases

| Release | Tag | Status |
|---------|-----|--------|
| MVP | `v0.1.0-mvp` | ✅ Abgeschlossen |
| UI + Diagnostics | `v0.2.0` | ✅ Abgeschlossen |
| Acceptance + Roadmap | `v0.3.0` | ✅ Abgeschlossen |
| **Build-Green Snapshot** | **`v3.1-build-green`** | ✅ **Aktuell** |

Siehe [CHANGELOG.md](../CHANGELOG.md) für Details.

---

## 🔗 Externe Links

- **GitHub Repo:** `bigbadboy1010/loupe`
- **Signaling Health:** `https://loupe.ddns.net/healthz`
- **WebSocket:** `wss://loupe.ddns.net/ws`
- **TURN/STUN:** `loupe.ddns.net:3478`

---

*Letztes Update: 2026-06-04*