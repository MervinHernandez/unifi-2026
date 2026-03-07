# Game Plan: Route YouTube TV Traffic via Nashville

## Overview

**Traffic Flow Goal:**
```
Apple TV (Orlando, AppleTV VLAN) → WireGuard Tunnel → Nashville UDM Pro → YouTube TV → Nashville WAN IP
```

YouTube TV uses your WAN IP to determine your market/local channels. By routing YouTube TV traffic through Nashville's WAN, YouTube TV will see a Nashville IP and serve the Nashville market.

### Network Reference

| Site | Device | Network Version | Default Subnet |
|---|---|---|---|
| Nashville, TN | WingMan UDM Pro | 10.1.85 | 192.168.1.0/24 |
| Orlando, FL | Anders Way UCG Max | 10.1.85 | (existing default, untouched) |
| Orlando, FL | AppleTV VLAN (new) | — | 192.168.50.0/24 |
| VPN Tunnel | Tailscale (WireGuard) | — | 100.x.x.x (auto-assigned by Tailscale) |

### Architecture

```
Anders Way default network ──────────────────────────────► Orlando WAN (unchanged)

Hardwood House AppleTV VLAN (192.168.50.0/24)
    └─► Tailscale tunnel (UniFi Express, policy routing)
            └─► Nashville Mac Mini (Tailscale exit node)
                    └─► ALL AppleTV VLAN traffic ─────────► Nashville WAN IP
                    └─► All other Hardwood traffic ───────► Hardwood WAN (unchanged)
```

The Anders Way **default network is completely untouched**. The VPN tunnel is scoped only to the new `192.168.50.0/24` AppleTV VLAN. Nashville never sees the existing Orlando default subnet.

---

## Confirmed Decisions

| Decision | Choice |
|---|---|
| VPN Protocol | UniFi Site Magic (WireGuard, cloud-assisted) |
| Traffic Identification | Domain-Based Traffic Routes |
| Subnet Strategy | New dedicated VLAN for Apple TV (`192.168.50.0/24`) — default Anders Way network untouched |

---

## High-Level Phase Order

```
Phase 1: Pre-flight checks (both sites)
Phase 2: Create AppleTV VLAN on Orlando UCG Max
Phase 3: Configure WireGuard Site-to-Site VPN (scoped to AppleTV VLAN)
Phase 4: Verify VPN tunnel is up
Phase 5: Configure domain-based Traffic Routes (Orlando side)
Phase 6: NAT verification (Nashville side)
Phase 7: Assign Apple TV to new VLAN
Phase 8: Test & validate YouTube TV market
```

---

## Phase 1: Pre-Flight Checks

### Nashville — WingMan UDM Pro
- [x] Confirm WAN IP shows Nashville location (visit whatismyip.com from Nashville)
- [x] Note WAN interface name: `WAN1`
- [x] Confirm firmware version: Settings → System → Updates → Network 10.1.85
- [x] Confirm `192.168.50.0/24` is not already in use anywhere on Nashville network
- [x] WAN IP type — static or dynamic?: `Static` / `68.53.130.216`

### Orlando — Anders Way UCG Max
- [x] Confirm firmware version: Settings → System → Updates → Network 10.8.85
- [x] Note Apple TV MAC address: `c4:f7:c1:3c:d7:1e`
- [x] Confirm `192.168.50.0/24` is not already in use on Orlando network
- [x] Note any existing VLANs and their IDs to avoid conflicts: `None`

---

## Phase 2: Create AppleTV VLAN — Orlando UCG Max

```
Settings → Networks → Create New Network
- Name: AppleTV
- Network Type: VLAN Only (or Corporate)
- VLAN ID: 50  (confirm unused)
- Subnet: 192.168.50.0/24
- Gateway: 192.168.50.1
- DHCP: Enabled
- DHCP Range: 192.168.50.100 – 192.168.50.200
```

- [x] AppleTV VLAN created
- [x] VLAN ID confirmed unused: `50`
- [x] DHCP enabled and range set

> This VLAN is isolated from the Anders Way default network. The default network is unaffected.

---

## Phase 2b: Xfinity Gateway — ~~DMZ Setup~~ (Eliminated)

> **No longer needed.** Switching to UniFi Site Magic removes all dependency on the Xfinity gateway. Site Magic uses outbound-initiated connections through UniFi's cloud relay — no DMZ, no port forwarding, no public IP exposure required.

---

## Phase 3: Tailscale VPN via Nashville Mac Mini

Tailscale uses WireGuard with built-in NAT traversal — no port forwarding, no DMZ, works through the Xfinity double-NAT on Nashville. The Nashville Mac Mini acts as a Tailscale **exit node**, and the Hardwood House UniFi Express is configured via SSH to route all AppleTV VLAN traffic through it.

> **Note on firmware updates:** Tailscale is installed via SSH outside of UniFi's official support. Firmware updates may require re-installing the Tailscale binary. The state file and boot script are stored in `/data/` which persists across updates.

---

### Step 3a — Nashville Mac Mini: Enable exit node

```bash
sudo tailscale up --advertise-exit-node
```

- [x] Exit node advertised on Mac Mini

### Step 3b — Approve exit node in Tailscale admin console

```
https://login.tailscale.com/admin/machines
→ Mac Mini → "..." → Edit route settings → Enable "Use as exit node" ✓
```

- [x] Exit node approved in admin console
- [x] Note Mac Mini's Tailscale hostname or IP (100.x.x.x): `100.98.194.40`

### Step 3c — SSH into Hardwood House UniFi Express

```bash
ssh root@192.168.2.1
```

- [x] SSH access confirmed
- [x] UX LAN IP noted: `192.168.2.1`

### Step 3d — Install Tailscale on UniFi Express (ARM64)

```bash

```

- [x] Tailscale installed — confirm with `tailscale version`

### Step 3e — Start tailscaled and authenticate

```bash
apt-get install tailscale -y
```

- [x] tailscaled running
- [x] Express authenticated and visible in Tailscale admin console

### Step 3f — Set Nashville Mac Mini as exit node

```bash
tailscale up \
  --exit-node=<mac-mini-tailscale-hostname-or-IP> \
  --exit-node-allow-lan-access=true
```

`--exit-node-allow-lan-access=true` ensures Hardwood House LAN devices remain reachable even though an exit node is set.

- [x] Exit node set to Nashville Mac Mini
- [x] Confirm with: `tailscale status` — Mac Mini shows as exit node

### Step 3g — Add policy routing to send AppleTV VLAN through Tailscale

```bash
# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# Confirm Tailscale interface name (usually tailscale0)
ip link show | grep tailscale

# Create a separate routing table (200) that routes everything out Tailscale
ip route add default dev tailscale0 table 200

# Apply that table to all traffic sourced from the AppleTV VLAN
ip rule add from 192.168.50.0/24 lookup 200 priority 100

# MASQUERADE: make VLAN 50 traffic appear as the Express's Tailscale IP
# so it routes correctly through the exit node
iptables -t nat -A POSTROUTING -s 192.168.50.0/24 -o tailscale0 -j MASQUERADE
```

- [ ] Policy routing rules applied
- [ ] Test: assign a laptop to VLAN 50, visit whatismyip.com — should show Nashville IP

### Step 3h — Make routing rules persistent across reboots

```bash
mkdir -p /data/on_boot.d
cat > /data/on_boot.d/99-tailscale-routing.sh << 'EOF'
#!/bin/sh
sleep 10  # wait for network to be ready
tailscaled --state=/data/tailscale/tailscaled.state &
sleep 5
tailscale up --exit-node=<mac-mini-hostname> --exit-node-allow-lan-access=true
sysctl -w net.ipv4.ip_forward=1
ip route add default dev tailscale0 table 200 2>/dev/null || true
ip rule add from 192.168.50.0/24 lookup 200 priority 100 2>/dev/null || true
iptables -t nat -A POSTROUTING -s 192.168.50.0/24 -o tailscale0 -j MASQUERADE
EOF
chmod +x /data/on_boot.d/99-tailscale-routing.sh
```

- [ ] Boot script created and executable
- [ ] Test persistence: reboot UX, re-check routing rules with `ip rule show` and `tailscale status`

---

## Phase 4: Verify VPN Tunnel

- [ ] Nashville: Settings → VPN → Site-to-Site VPN — tunnel shows **Connected**
- [ ] Orlando: Settings → VPN → Site-to-Site VPN — tunnel shows **Connected**
- [ ] Temporarily assign a laptop/device to the AppleTV VLAN (192.168.50.x), then ping `10.100.0.1` (Nashville tunnel IP) — should succeed
- [ ] Ping Nashville LAN gateway `192.168.1.1` from that device — should succeed
- [ ] Confirm Anders Way default network devices are unaffected (ping their gateway, browse normally)

---

## Phase 5: Domain-Based Traffic Routes — Not Required

> **With the Tailscale approach, domain-based Traffic Routes are not needed.** The policy routing rules from Phase 3g route ALL AppleTV VLAN (`192.168.50.0/24`) traffic through the Tailscale tunnel at the kernel level — before DNS interception. Every connection from an AppleTV VLAN device exits through Nashville WAN automatically.
>
> This is simpler and more reliable than domain-based routing: no risk of missed domains, hardcoded IPs, or CDN bypasses.

- [x] Domain-based Traffic Routes — skipped (not needed with Tailscale policy routing)

---

## Phase 6: NAT Verification — Nashville Mac Mini (Tailscale Exit Node)

With Tailscale, the Nashville Mac Mini performs NAT automatically when acting as an exit node — all traffic forwarded through it exits Nashville WAN as the Mac Mini's IP (which is NATted by the Nashville router to the Nashville public WAN IP `68.53.130.216`).

**Verify this is working:**
```bash
# On the Nashville Mac Mini — confirm IP forwarding is enabled (Tailscale enables this automatically)
sysctl net.inet.ip.forwarding   # macOS
# Expected: net.inet.ip.forwarding = 1
```

If traffic isn't exiting Nashville (YouTube TV still shows wrong market after Phase 8 testing):
```bash
# On Nashville Mac Mini — confirm Tailscale sees the Express as a connected client
tailscale status
# Express should appear in the list

# Check exit node is active
tailscale status | grep -i exit
```

- [ ] Nashville Mac Mini IP forwarding confirmed active (Tailscale manages this)
- [ ] Express visible in `tailscale status` on Mac Mini

---

## Phase 7: Assign Apple TV to AppleTV VLAN

### If Apple TV is wired:
```
UniFi Network → Ports → [port Apple TV is connected to]
- Port Profile: AppleTV  (the VLAN created in Phase 2)
```

### If Apple TV is on WiFi:
```
Settings → WiFi → Create New SSID
- Name: [e.g., "AppleTV-Nash" or hidden SSID]
- Network: AppleTV (VLAN 50)
- Security: WPA2/WPA3
```
Then connect Apple TV to this SSID.

- [ ] Apple TV connected to AppleTV VLAN
- [ ] Apple TV receives IP in `192.168.50.x` range — confirm in:
  - Network → Clients → find Apple TV → note IP address

---

## Phase 8: Test & Validate

- [ ] On Apple TV: open YouTube TV → Settings → Area — confirm shows **Nashville** market
- [ ] Confirm WAN IP from Apple TV browser shows Nashville IP (visit whatismyip.com in browser or AltStore)
- [ ] On a default Anders Way network device: confirm WAN IP still shows Orlando IP (unchanged)
- [ ] On Apple TV: test a YouTube TV live stream — confirm playback quality is acceptable
- [ ] Run speed test from Apple TV — note latency (Orlando → Nashville round trip is expected, typically 20–40ms added)
- [ ] Test for a few days — confirm no VPN tunnel drops (Settings → VPN on either console)

---

## Ongoing Considerations

| Item | Note |
|---|---|
| **Nashville WAN IP** | If dynamic, use DDNS hostname in WireGuard config — avoids tunnel breaking on IP change |
| **YouTube TV domain changes** | Domain-based routing auto-adapts; no maintenance needed for IP changes |
| **Bandwidth** | YouTube TV uses ~13–20 Mbps per stream. All streams traverse Nashville WAN upstream |
| **Apple TV wired vs wireless** | Wired strongly preferred — eliminates WiFi as a variable |
| **Tunnel monitoring** | Periodically check Settings → VPN → Site-to-Site VPN on both consoles for uptime |
| **Adding more devices** | Assign any device to the AppleTV VLAN (VLAN 50) to route its YouTube TV traffic via Nashville |

---

## Status Tracker

| Phase | Status | Notes |
|---|---|---|
| Decision 1: VPN Protocol | Updated — Tailscale via Nashville Mac Mini exit node | No port forwarding needed; works through double-NAT |
| Decision 2: Domain-Based Traffic Routes | Confirmed | |
| Decision 3: AppleTV VLAN (192.168.50.0/24) | Confirmed | Default Anders Way network untouched |
| Phase 1: Pre-flight checks | Complete | Nashville public IP: 68.53.130.216 |
| Phase 2: Create AppleTV VLAN (Orlando) | Complete | 192.168.50.0/24, VLAN 50 |
| Phase 2b: Xfinity DMZ (Nashville) | Eliminated | Not needed — Tailscale works through double-NAT |
| Phase 3: Tailscale VPN setup | Not started | Nashville Mac Mini as exit node; SSH into UX |
| Phase 4: VPN tunnel verified | Not started | |
| Phase 5: Domain Traffic Routes | Eliminated | Not needed — all VLAN 50 traffic routes via Nashville at kernel level |
| Phase 6: NAT verification (Nashville Mac Mini) | Not started | Tailscale handles automatically; verify with tailscale status |
| Phase 7: Apple TV assigned to VLAN | Not started | |
| Phase 8: Testing | Not started | |
