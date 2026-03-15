# Step 3b1 — Connect Personal Laptop Directly to Nashville WireGuard (Remote Test)

**Context:** You are in Wisconsin. The WireGuard server (WingManWG) is running on the Nashville UDM Pro at `nashville.mervinhernandez.com:51820`. You want to connect your laptop directly as a WireGuard client and verify YouTube TV sees Nashville.

---

## What You Need First (from Nashville UDM Pro)

1. Log in to Nashville UDM Pro > **Settings > VPN > VPN Server > WingManWG**
2. Click **Add Client** (or "Create Client"):
   - Name: `LaptopTest` (or your choice)
   - Tunnel IP: `10.20.0.10` (or pick any unused address in `10.20.0.0/24`)
3. Download or copy the client `.conf` file — it will look like:

```ini
[Interface]
PrivateKey = <client-private-key>
Address = 10.20.0.10/24
DNS = 1.1.1.1

[Peer]
PublicKey = <server-public-key>
Endpoint = nashville.mervinhernandez.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

> **Important:** Confirm `AllowedIPs = 0.0.0.0/0` so ALL traffic routes through the tunnel (not split-tunnel). This is needed for YouTube TV to see Nashville.

---

## Install WireGuard on Your Laptop

| OS | Install |
|----|---------|
| macOS | [wireguard.com/install](https://www.wireguard.com/install/) or `brew install wireguard-tools` |
| Windows | [wireguard.com/install](https://www.wireguard.com/install/) |
| Linux | `apt install wireguard` / `dnf install wireguard-tools` |

The easiest option is the **WireGuard GUI app** (macOS/Windows) — it lets you import the `.conf` file directly.

---

## Import and Connect

### macOS / Windows (GUI)
1. Open WireGuard app
2. **Import tunnel from file** — select the `.conf` file
3. Toggle **Activate**

### macOS / Linux (CLI)
```bash
sudo wg-quick up /path/to/LaptopTest.conf
```

To disconnect:
```bash
sudo wg-quick down /path/to/LaptopTest.conf
```

---

## Verify It's Working

Once connected, open a browser and visit:

- **[whatismyip.com](https://www.whatismyip.com)** — should show Nashville WAN IP (`68.84.90.8` or current)
- **[iplocation.net](https://www.iplocation.net)** — should show Nashville, TN

If both show Nashville, your traffic is exiting through the Nashville WAN correctly.

---

## Test YouTube TV

1. Open YouTube TV on your laptop
2. Navigate to **Settings > Area** (or start watching live TV)
3. YouTube TV should detect the Nashville market and show Nashville local channels

> YouTube TV caches location. If it still shows Wisconsin, sign out and back in, or wait a few minutes and refresh.

---

## Troubleshoot

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Tunnel won't connect | Firewall blocking UDP 51820 | Verify the "Allow WireGuard Server" rule is active on UDM Pro WAN |
| Tunnel connects but IP is not Nashville | Split-tunnel / wrong AllowedIPs | Ensure `AllowedIPs = 0.0.0.0/0` in client config |
| YouTube TV shows wrong market | YT TV location cache | Sign out/in or try incognito mode |
| Tunnel drops after idle | Keepalive not set | Add `PersistentKeepalive = 25` to `[Peer]` section |
| Can't reach Nashville UDM Pro | DDNS not resolving | Run `nslookup nashville.mervinhernandez.com` — should return `68.84.90.8` |

---

## When Done Testing

- Disconnect the tunnel (toggle off in app, or `sudo wg-quick down`)
- The Nashville WireGuard server will still be running for Phase 3c (Orlando client configs)
- Mark Step 3b1 complete in GAME_PLAN.md and proceed to Step 3c

---

## Key Reference

| Item | Value |
|------|-------|
| WireGuard server | `WingManWG` on Nashville UDM Pro |
| Server endpoint | `nashville.mervinhernandez.com:51820` |
| Tunnel subnet | `10.20.0.0/24` |
| Suggested laptop tunnel IP | `10.20.0.10/24` |
| Nashville WAN IP | `68.84.90.8` (DDNS auto-updates if it changes) |
