---
name: Bug report
about: Something broke while using Loupe
title: "[bug] "
labels: bug
assignees: ""
---

## What happened?

A clear, one-paragraph description of the bug.

## What did you expect to happen?

What you thought would happen instead.

## How can we reproduce it?

Steps, ideally numbered. If the bug needs a specific environment (display setup, network, permissions), call it out.

```
1. Host: macOS <version>, Mac model, Screen Recording + Accessibility granted: yes/no
2. Controller: iOS <version>, iPhone/iPad model, Loupe build <version>
3. Network: same Wi-Fi / different network / VPN / corporate firewall
4. Steps:
   - Run `swift run LoupeHost`
   - Open LoupeControllerApp on iPhone
   - Scan QR / paste token
   - <the thing that breaks>
```

## What did you see?

Logs, screenshots, screen recordings. From the Host side: `~/Library/Logs/com.miggu69.loupe/` (path may differ per build). From the Controller side: in-app Diagnostics tab.

## Severity

- [ ] Blocker — can't connect at all
- [ ] High — connects but unusable
- [ ] Medium — works around a known limitation
- [ ] Low — cosmetic, doesn't affect the connection

## What you've already tried

Optional but very helpful. E.g. "rebooted Mac", "killed the controller and re-paired", "tried on cellular".
