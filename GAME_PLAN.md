# Game Plan: Route YouTube TV Traffic via Nashville

## Overview

**Traffic Flow Goal:**
```
Apple TV / Mobile (Orlando) → VPN Tunnel → Nashville UDM Pro → YouTube TV → Nashville WAN IP
```

YouTube TV uses your WAN IP to determine your market/local channels. By routing YouTube TV traffic through Nashville's WAN, YouTube TV will see a Nashville IP and serve the Nashville market.

### Network Reference

| Site | Device | Network Version | Default Subnet |
|---|---|---|---|
| Nashville, TN | WingMan UDM Pro | 10.1.85 | 192.168.1.0/24 |
| Orlando, FL | Anders Way UCG Max | 10.1.85 | TBD |

---

## Prerequisites: Decisions Needed Before Starting

### Decision 1: Site-to-Site VPN Protocol

Two native UniFi options on v10.1.85:

| | IPsec (IKEv2) | WireGuard |
|---|---|---|
| **Native UniFi UI** | Yes, full UI | Yes, full UI (UCG Max + UDM Pro both support) |
| **Performance** | Good | Better (lower overhead) |
| **Config complexity** | Moderate | Simpler |
| **Reliability** | Very mature | Modern, very stable |
| **Recommendation** | Either works | Preferred if both devices support it |

> **Confirm**: Do you want to use **WireGuard** or **IPsec** for the Site-to-Site VPN?

- [ ] Decision made: _______________

---

### Decision 2: How to Identify YouTube TV Traffic

Three approaches:

| | Domain-Based Traffic Routes | Dedicated VLAN | Full Tunnel VPN |
|---|---|---|---|
| **How it works** | Route `*.youtube.com`, `*.googlevideo.com` etc. through Nashville per-device or network-wide | Put Apple TV + mobile on a VLAN where ALL traffic exits via Nashville | All Orlando traffic exits Nashville (sledgehammer approach) |
| **Granularity** | Fine — only YT traffic routed, everything else uses Orlando WAN | Medium — entire VLAN goes via Nashville | None — everything goes via Nashville |
| **UniFi UI support** | Traffic Routes (v8+, works in 10.x) | VLANs + Traffic Routes | Site-to-site default route |
| **Risk** | Low — other traffic unaffected | Low-Medium — other apps on those devices use Nashville | High — affects all Orlando internet |
| **Recommendation** | Best option | Good if you want simpler rules | Avoid |

> **Confirm**: Do you want **domain-based Traffic Routes** (surgical, only YouTube TV traffic) or a **dedicated VLAN** (all traffic from Apple TV / specific devices goes via Nashville)?

- [ ] Decision made: _______________

---

### Decision 3: Pre-flight Subnet Confirmation

> ⚠️ **Both sites CANNOT use the same subnet** for Site-to-Site VPN to work. If Orlando is also on `192.168.1.0/24`, one site must be changed before the VPN is configured.

- [ ] Confirm Orlando (Anders Way UCG Max) current LAN subnet: _______________
- [ ] Confirm Nashville WAN IP is static or dynamic: _______________
- [ ] If dynamic, confirm DDNS is configured on UDM Pro (Settings → Internet → Dynamic DNS): _______________

---

## High-Level Phase Order

```
Phase 1: Pre-flight checks (both sites)
Phase 2: Site-to-Site VPN setup
Phase 3: Verify VPN tunnel is up
Phase 4: Traffic routing configuration (Orlando side)
Phase 5: NAT verification (Nashville side)
Phase 6: Test & validate YouTube TV market
Phase 7: Cleanup & documentation
```

---

## Phase 1: Pre-Flight Checks

### Nashville — WingMan UDM Pro
- [ ] Note current WAN IP (confirm it shows Nashville via whatismyip.com)
- [ ] Note WAN interface name (usually `eth8` or `WAN`)
- [ ] Confirm firmware: Settings → System → Updates → version: _______________
- [ ] Note Default Network subnet: `192.168.1.0/24`
- [ ] Confirm WAN IP stability — set up DDNS if dynamic:
  - Settings → Internet → [WAN interface] → Dynamic DNS

### Orlando — Anders Way UCG Max
- [ ] Note current WAN IP
- [ ] Note LAN subnet: _______________
- [ ] Confirm firmware: Settings → System → Updates → version: _______________
- [ ] Identify Apple TV MAC address: _______________
- [ ] Identify any mobile devices to include: _______________

---

## Phase 2: Site-to-Site VPN Setup

### Option A: WireGuard *(complete if Decision 1 = WireGuard)*

**Nashville (UDM Pro) — Server/Listener side:**
```
Settings → VPN → Site-to-Site VPN → Create → WireGuard
- Role: Server
- Local WAN: [your WAN interface]
- Tunnel IP: 10.100.0.1/30
- Port: 51820 (default)
- Note the Public Key generated: _______________
```
- [ ] Nashville WireGuard server created
- [ ] Public key noted

**Orlando (UCG Max) — Client/Initiator side:**
```
Settings → VPN → Site-to-Site VPN → Create → WireGuard
- Role: Client
- Server Address: [Nashville WAN IP or DDNS hostname]
- Server Public Key: [from Nashville step above]
- Tunnel IP: 10.100.0.2/30
- Allowed IPs: (specific routes or 0.0.0.0/0 depending on Decision 2)
```
- [ ] Orlando WireGuard client created

---

### Option B: IPsec (IKEv2) *(complete if Decision 1 = IPsec)*

**Nashville (UDM Pro):**
```
Settings → VPN → Site-to-Site VPN → Create → IPsec
- Name: To-Orlando
- Remote Subnet: [Orlando LAN subnet]
- Preshared Key: [generate a strong key and note it]
- Local WAN IP: [Nashville WAN IP]
```
- [ ] Nashville IPsec config created
- [ ] Preshared key noted

**Orlando (UCG Max):**
```
Settings → VPN → Site-to-Site VPN → Create → IPsec
- Name: To-Nashville
- Remote IP: [Nashville WAN IP or DDNS hostname]
- Remote Subnet: 192.168.1.0/24
- Preshared Key: [same key from Nashville]
- Local WAN IP: [Orlando WAN IP]
```
- [ ] Orlando IPsec config created

---

## Phase 3: Verify VPN Tunnel

- [ ] Nashville: Settings → VPN → Site-to-Site VPN — tunnel shows **Connected**
- [ ] Orlando: Settings → VPN → Site-to-Site VPN — tunnel shows **Connected**
- [ ] From Orlando network, ping Nashville LAN gateway (e.g. `192.168.1.1`) — succeeds
- [ ] Confirm Orlando devices are NOT yet appearing in Nashville client list (traffic not routed yet — expected)

---

## Phase 4: Traffic Routing — Orlando Side

### Option A: Domain-Based Traffic Routes *(complete if Decision 2 = Domain-Based)*

```
Settings → Traffic Management → Traffic Routes → Create Route
- Name: YouTube TV via Nashville
- Interface: [Site-to-Site VPN tunnel]
- Matching: Domain
  Add the following domains:
    - youtube.com
    - googlevideo.com
    - googleapis.com
    - ggpht.com
    - ytimg.com
    - youtubekids.com
    - youtubei.googleapis.com
- Apply to: All clients (or specify network/device)
```

- [ ] Traffic route created
- [ ] Domains added
- [ ] Applied to correct clients/network

> Note: UniFi uses DNS-based interception for domain routes. If CDN IPs are not resolving correctly, add supplemental IP-based routes for Google's AS15169 ranges.

---

### Option B: Dedicated VLAN *(complete if Decision 2 = Dedicated VLAN)*

**Step 1 — Create the VLAN network:**
```
Settings → Networks → Create Network
- Name: Nashville-Exit
- VLAN ID: 20 (or choose an unused ID)
- Subnet: 192.168.20.0/24
- Purpose: Corporate
```
- [ ] Nashville-Exit VLAN created

**Step 2 — Create WiFi SSID for mobile devices (if needed):**
```
Settings → WiFi → Create
- Name: [your choice, e.g. "Nashville"]
- Network: Nashville-Exit
- Security: WPA2/WPA3
```
- [ ] WiFi SSID created (or skip if wired only)

**Step 3 — Create Traffic Route for the VLAN:**
```
Settings → Traffic Management → Traffic Routes → Create Route
- Name: Nashville-Exit Full Tunnel
- Interface: [VPN tunnel]
- Source: Nashville-Exit network (192.168.20.0/24)
- Destination: 0.0.0.0/0
```
- [ ] Traffic route created

**Step 4 — Assign Apple TV to VLAN:**
- Wired: plug Apple TV into a port assigned to VLAN 20
  - Settings → Ports → [port] → Port Profile → Nashville-Exit
- Wireless: connect Apple TV to the Nashville WiFi SSID

- [ ] Apple TV assigned to Nashville-Exit VLAN

---

## Phase 5: NAT Verification — Nashville Side

UniFi auto-configures masquerade NAT on WAN — verify it is active:

```
Settings → Routing → NAT
- Confirm masquerade/outbound NAT rule exists for WAN interface
```

If YouTube TV traffic arrives at Nashville but doesn't exit properly, add a manual rule:
```
Settings → Security → Traffic & Firewall Rules → NAT
- Type: Masquerade
- Source: [Orlando VPN subnet]
- Outbound Interface: WAN
```

- [ ] NAT confirmed active on Nashville WAN

---

## Phase 6: Test & Validate

- [ ] On Apple TV (Orlando): Open YouTube TV → Settings → Area → confirm shows **Nashville** market
- [ ] Check WAN IP from a browser on the routed device — should show Nashville WAN IP
- [ ] Confirm other Orlando devices (non-YouTube TV devices / non-VLAN) still use Orlando WAN IP
- [ ] Run speed test from Apple TV — note any latency increase (Orlando → Nashville → back is expected)
- [ ] Test YouTube TV streaming quality — confirm acceptable

---

## Phase 7: Ongoing Considerations

| Item | Note |
|---|---|
| **Nashville WAN IP stability** | If dynamic, use DDNS hostname in VPN config — Settings → Internet → Dynamic DNS |
| **YouTube TV domain changes** | Domain-based routing handles Google CDN IP changes automatically |
| **Bandwidth** | All YouTube TV traffic traverses Nashville WAN upstream — confirm Nashville has sufficient bandwidth |
| **Apple TV wired vs wireless** | Wired preferred for stability |
| **VPN tunnel monitoring** | Check Settings → VPN → Site-to-Site VPN periodically for disconnect events |

---

## Status Tracker

| Phase | Status | Notes |
|---|---|---|
| Decision 1: VPN Protocol | Pending | |
| Decision 2: Traffic Method | Pending | |
| Decision 3: Subnet / WAN confirmation | Pending | |
| Phase 1: Pre-flight checks | Not started | |
| Phase 2: VPN setup | Not started | |
| Phase 3: VPN tunnel verified | Not started | |
| Phase 4: Traffic routing | Not started | |
| Phase 5: NAT verification | Not started | |
| Phase 6: Testing | Not started | |
| Phase 7: Cleanup | Not started | |
