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
| VPN Tunnel | WireGuard | — | 10.100.0.0/30 |

### Architecture

```
Anders Way default network ──────────────────────────────► Orlando WAN (unchanged)

Anders Way AppleTV VLAN (192.168.50.0/24)
    └─► WireGuard Tunnel (10.100.0.0/30)
            └─► Nashville UDM Pro
                    └─► YouTube TV domains only ──────────► Nashville WAN IP
                    └─► All other traffic ────────────────► Nashville WAN (passthrough)
```

The Anders Way **default network is completely untouched**. The VPN tunnel is scoped only to the new `192.168.50.0/24` AppleTV VLAN. Nashville never sees the existing Orlando default subnet.

---

## Confirmed Decisions

| Decision | Choice |
|---|---|
| VPN Protocol | WireGuard |
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
- [x] WAN IP type — static or dynamic?: `Static`

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

## Phase 3: WireGuard Site-to-Site VPN

### Step 3a — Nashville (UDM Pro) — Server side

```
Settings → VPN → Site-to-Site VPN → Create → WireGuard
- Name: To-Orlando-AppleTV
- Role: Server
- Local WAN Interface: [your WAN interface]
- Listen Port: 51820
- Tunnel IP: 10.100.0.1/30
- Peer (Orlando) Allowed IPs: 192.168.50.0/24
```

- [ ] Nashville WireGuard server created
- [ ] Nashville Public Key (copy this — needed for Orlando): _______________
- [ ] Listen port confirmed open (check firewall rules — port 51820 UDP)

### Step 3b — Orlando (UCG Max) — Client side

```
Settings → VPN → Site-to-Site VPN → Create → WireGuard
- Name: To-Nashville
- Role: Client
- Server Address: [Nashville WAN IP or DDNS hostname]
- Server Port: 51820
- Server Public Key: [Nashville public key from Step 3a]
- Tunnel IP: 10.100.0.2/30
- Allowed IPs: 0.0.0.0/0
  (Traffic Routes in Phase 5 will control what actually uses the tunnel — this allows full routing flexibility)
- Pre-shared Key: [generate one, set same on both sides]
```

- [ ] Orlando WireGuard client created
- [ ] Nashville server address entered: _______________
- [ ] Pre-shared key set on both sides

### Step 3c — Nashville: Add return route to Orlando AppleTV VLAN

Nashville needs to know how to route return traffic back to `192.168.50.0/24` through the tunnel.

```
Settings → Routing → Static Routes → Create
- Name: Orlando-AppleTV-Return
- Destination: 192.168.50.0/24
- Gateway / Interface: [WireGuard tunnel interface]
```

- [ ] Static return route created on Nashville

---

## Phase 4: Verify VPN Tunnel

- [ ] Nashville: Settings → VPN → Site-to-Site VPN — tunnel shows **Connected**
- [ ] Orlando: Settings → VPN → Site-to-Site VPN — tunnel shows **Connected**
- [ ] Temporarily assign a laptop/device to the AppleTV VLAN (192.168.50.x), then ping `10.100.0.1` (Nashville tunnel IP) — should succeed
- [ ] Ping Nashville LAN gateway `192.168.1.1` from that device — should succeed
- [ ] Confirm Anders Way default network devices are unaffected (ping their gateway, browse normally)

---

## Phase 5: Domain-Based Traffic Routes — Orlando UCG Max

```
Settings → Traffic Management → Traffic Routes → Create Route
- Name: YouTube TV via Nashville
- Interface: [WireGuard VPN tunnel — To-Nashville]
- Matching Type: Domain
  Add domains:
    youtube.com
    googlevideo.com
    googleapis.com
    ggpht.com
    ytimg.com
    youtubekids.com
    youtubei.googleapis.com
    googleusercontent.com
- Apply to: AppleTV network (192.168.50.0/24)
```

- [ ] Traffic route created
- [ ] All domains added
- [ ] Route scoped to AppleTV VLAN only

> UniFi intercepts DNS responses for matched domains and routes those IPs through the tunnel. If any YouTube TV CDN traffic bypasses DNS (hardcoded IPs), a supplemental IP-based route for Google AS15169 may be needed — address this in testing if streams don't work.

---

## Phase 6: NAT Verification — Nashville UDM Pro

UniFi auto-configures masquerade NAT on WAN. Verify it covers VPN-originated traffic:

```
Settings → Routing → NAT (or Firewall & Security → NAT)
- Confirm an outbound masquerade rule exists for WAN interface covering all sources
```

If YouTube TV traffic arrives at Nashville but doesn't exit to the internet properly, add:
```
Settings → Security → Traffic & Firewall Rules → NAT → Create
- Rule Type: Masquerade
- Source: 192.168.50.0/24  (Orlando AppleTV VLAN)
- Outbound Interface: WAN
```

- [ ] NAT confirmed active on Nashville WAN
- [ ] Manual NAT rule added if needed: Yes / No

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
| Decision 1: WireGuard | Confirmed | |
| Decision 2: Domain-Based Traffic Routes | Confirmed | |
| Decision 3: AppleTV VLAN (192.168.50.0/24) | Confirmed | Default Anders Way network untouched |
| Phase 1: Pre-flight checks | Not started | |
| Phase 2: Create AppleTV VLAN (Orlando) | Not started | |
| Phase 3: WireGuard VPN setup | Not started | |
| Phase 4: VPN tunnel verified | Not started | |
| Phase 5: Domain Traffic Routes (Orlando) | Not started | |
| Phase 6: NAT verification (Nashville) | Not started | |
| Phase 7: Apple TV assigned to VLAN | Not started | |
| Phase 8: Testing | Not started | |
