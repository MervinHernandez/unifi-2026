# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This is a **network infrastructure project**, not a software project. The goal is to route YouTube TV traffic from two Orlando, FL UniFi sites through a Nashville, TN WireGuard VPN server so YouTube TV detects the Nashville market and serves Nashville local channels. All other traffic remains on local WAN.

## Architecture

**Three-site topology:**

| Site | Device | Subnet | Role |
|------|--------|--------|------|
| Nashville, TN | WingMan UDM Pro | 192.168.1.0/24 | WireGuard server + WAN exit point |
| Orlando (Anders Way) | UCG Max | 192.168.1.0/24 | WireGuard client |
| Orlando (Hardwood House) | UX | 192.168.2.0/24 | WireGuard client |

**WireGuard tunnel:**
- Tunnel subnet: `10.20.0.0/24`
- Server endpoint: `nashville.mervinhernandez.com:51820` (Cloudflare DDNS → 68.84.90.8)
- Port: 51820 UDP

**Traffic routing strategy:** Dedicated VLAN 50 (192.168.50.0/24) for streaming devices (Apple TVs). Policy-based routing sends all VLAN 50 traffic through the WireGuard tunnel. Other VLANs use local WAN directly.

## Implementation Status

Tracked in `GAME_PLAN.md` with 9 phases:
- ✅ Phase 1: Pre-flight checks (all three sites)
- ✅ Phase 2: Cloudflare DDNS on Nashville
- ⏳ Phase 3: Nashville WireGuard server setup
- ⏳ Phase 4–5: Orlando VLAN + WireGuard client setup
- ⏳ Phase 6–9: Verification and device assignment

## Scripts

### `scripts/youtube-split-tunnel.sh`

An **alternative/optional utility** — not part of the main VLAN-based implementation. Used for split-tunneling only YouTube/Google traffic on a per-device basis (e.g., laptop testing).

```bash
# Default: reads ~/Desktop/wireguard-export.zip
./scripts/youtube-split-tunnel.sh

# Or specify a path
./scripts/youtube-split-tunnel.sh ~/path/to/wireguard-export.zip
```

Fetches Google's current IP ranges from `gstatic.com`, patches `AllowedIPs` in all `.conf` files inside the zip, and outputs `~/Desktop/wireguard-youtube-split.zip` ready to re-import into the macOS WireGuard app.

## Key Reference Values

- Nashville WAN IP: `68.84.90.8`
- DDNS hostname: `nashville.mervinhernandez.com`
- WireGuard test client IP (laptop): `10.20.0.10/24`
- Streaming VLAN: VLAN 50 (`192.168.50.0/24`)
- DNS for tunnel clients: `1.1.1.1`

## Docs

- `GAME_PLAN.md` — master implementation plan with full checklists, UniFi UI steps, and rollback notes
- `README-step-3b1.md` — laptop remote test guide (connect personally to Nashville WireGuard before configuring Orlando sites)
