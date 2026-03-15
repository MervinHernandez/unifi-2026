# Game Plan: Route YouTube TV Traffic via Nashville

## Overview

**Traffic Flow Goal:**

```
Anders Way (Orlando) Apple TV / mobile  ---> WireGuard Tunnel ---> Nashville UDM Pro WAN ---> YouTube TV sees Nashville market
Hardwood House (Orlando) Apple TV / mobile ---> WireGuard Tunnel ---> Nashville UDM Pro WAN ---> YouTube TV sees Nashville market
```

YouTube TV uses your WAN IP to determine your market/local channels. By routing YouTube TV traffic through Nashville's WAN, YouTube TV sees a Nashville IP and serves the Nashville market.

### Network Reference

| Site | Device | Network Version | Default Subnet | Role |
| --- | --- | --- | --- | --- |
| Nashville, TN | WingMan UDM Pro | 10.1.85 | 192.168.1.0/24 | WireGuard Server + WAN exit point |
| Orlando, FL | Anders Way UCG Max | 10.1.85 | 192.168.1.0/24 | WireGuard Client |
| Orlando, FL | Hardwood House UX | 9.0.114 | 192.168.2.0/24 | WireGuard Client |

### Key Constraints

| Constraint | Detail |
| --- | --- |
| No UniFi Site-to-Site | Account owners differ across sites — Site Magic / Site-to-Site VPN is not available |
| Only YouTube TV traffic | Default internet traffic stays on each site's own WAN — only YouTube TV routes through Nashville |
| Nashville WAN | UDM Pro has the public IP directly (Xfinity/Comcast gateway in bridge mode) |
| Dynamic DNS needed | Nashville WAN IP may change — DDNS provides a stable WireGuard endpoint |

### Architecture

```
Anders Way default traffic ──────────────────────────────────► Anders Way WAN (unchanged)
Anders Way AppleTV VLAN (192.168.50.0/24)
    └─► WireGuard tunnel to Nashville UDM Pro
            └─► ALL AppleTV VLAN traffic ────────────────────► Nashville WAN IP (YouTube TV sees Nashville)

Hardwood House default traffic ──────────────────────────────► Hardwood WAN (unchanged)
Hardwood House AppleTV VLAN (192.168.50.0/24)
    └─► WireGuard tunnel to Nashville UDM Pro
            └─► ALL AppleTV VLAN traffic ────────────────────► Nashville WAN IP (YouTube TV sees Nashville)
```

> **Why a dedicated VLAN instead of domain-based routing?**
YouTube TV uses Google CDN IPs that overlap with other Google services, change frequently, and can't be reliably targeted by domain alone. A dedicated VLAN for streaming devices (Apple TVs, etc.) is simpler and more reliable — all traffic from those devices exits Nashville. For mobile devices, connect to the AppleTV WiFi SSID when you want Nashville routing, and use the normal WiFi otherwise.
>

---

## Confirmed Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| VPN Protocol | Native WireGuard on UDM Pro | Built-in, no third-party dependencies, fast |
| Nashville endpoint stability | Cloudflare DDNS (existing domain) | Stable hostname via Cloudflare API; no extra accounts needed |
| Traffic scoping | Dedicated AppleTV VLAN per site | Routes all VLAN traffic through tunnel; default networks untouched |
| Tunnel topology | Hub-and-spoke (Nashville = hub) | Both Orlando sites connect independently to Nashville |

---

## High-Level Phase Order

```
Phase 1: Pre-flight checks (all three sites)
Phase 2: Nashville — Configure DDNS on UDM Pro
Phase 3: Nashville — Configure WireGuard Server on UDM Pro
Phase 4: Anders Way — Create AppleTV VLAN + WireGuard Client
Phase 5: Hardwood House — Create AppleTV VLAN + WireGuard Client
Phase 6: Verify tunnels are up (both Orlando sites)
Phase 7: NAT verification (Nashville side)
Phase 8: Assign devices to AppleTV VLANs
Phase 9: Test & validate YouTube TV market
```

---

## ✅ Phase 1: Pre-Flight Checks

### ✅ Nashville — WingMan UDM Pro

- [x]  Confirm WAN IP shows Nashville location (visit [whatismyip.com](http://whatismyip.com/) from a Nashville device)
- [x]  Note current WAN IP: `68.84.90.8`
- [x]  Confirm Comcast/Xfinity gateway is in bridge mode (UDM Pro has public IP directly on WAN — confirmed: 68.84.90.8 on WAN1)
- [x]  Confirm firmware version: Settings > System > Updates > Network 10.1.85
- [x]  Confirm `192.168.50.0/24` is NOT in use on Nashville network
- [x]  Confirm WireGuard tunnel subnet doesn't conflict — using `10.20.0.0/24` (note: `10.10.0.0/24` is reserved by Xfinity gateway admin interface)

### ✅ Anders Way — UCG Max (Orlando)

- [x]  Confirm firmware version: Settings > System > Updates > Network 10.1.85
- [x]  Note Apple TV MAC address(es): `c4:f7:c1:3c:d7:1e`
- [ ]  ~~Note mobile device MAC addresses (if fixed-assigning): `___________`~~
- [x]  Confirm `192.168.50.0/24` is NOT in use on Anders Way network
- [x]  Confirm no existing VLANs conflict with VLAN ID 50
- [x]  Confirm WireGuard is available: Settings > VPN > VPN Client (check if WireGuard option exists)

### ✅ Hardwood House — UX (Orlando)

- [x]  Confirm firmware version: Settings > System > Updates > Network 9.0.114
- [x]  Check if WireGuard VPN Client is available on firmware 9.0.114 (Settings > VPN > VPN Client)
- [x]  Note Apple TV - Living Room - MAC address(es): `9c:3e:53:03:d3:2a`
- [x]  Note Apple TV - Bedroom - MAC Address(es): `6c:4a:85:18:c0:1b`
- [x]  Confirm `192.168.50.0/24` is NOT in use (default is 192.168.2.0/24, so likely fine)
- [x]  Confirm no existing VLANs conflict with VLAN ID 50

---

## ✅ Phase 2: Nashville — Configure Cloudflare DDNS on UDM Pro

The UDM Pro needs a stable hostname so the Orlando WireGuard clients can always find it, even if Comcast changes the WAN IP. Since you already have a domain managed on Cloudflare (with existing tunnels/services), Cloudflare is the natural DDNS provider — no extra accounts needed.

### ✅ Step 2a — Create Cloudflare API Token

```
Cloudflare Dashboard > My Profile > API Tokens > Create Token
- Template: "Edit zone DNS"
- Zone Resources: Include > Specific zone > [your domain]
- Permissions: Zone / DNS / Edit
- Create Token
- Copy the token value (you won't see it again)
```

- [x]  Cloudflare API token created with Zone.DNS edit permission
- [x]  Token value saved securely

### ✅ Step 2b — Create DNS A Record

```
Cloudflare Dashboard > [your domain] > DNS > Records > Add Record
- Type: A
- Name: wingman (or whatever subdomain you prefer, e.g., nashville.mervinhernandez.com)
- IPv4 address: [current Nashville WAN IP from Phase 1]
- Proxy status: DNS only (grey cloud — NOT proxied)
- TTL: Auto (or 1 min for faster propagation during setup)
```

> **Critical:** The record MUST be **DNS only** (grey cloud / proxy OFF). If Cloudflare's proxy is enabled (orange cloud), WireGuard will connect to Cloudflare's edge IP instead of Nashville — and Cloudflare doesn't proxy UDP, so WireGuard will fail silently.
>
- [x]  DNS A record created: `nashville.mervinhernandez.com` (or your chosen subdomain)
- [x]  Proxy status confirmed **DNS only** (grey cloud)
- [x]  Record resolves to Nashville WAN IP: `68.84.90.8`

### ✅ Step 2c — Configure DDNS on UDM Pro

```
Settings > Internet > WAN > Dynamic DNS > Create New
- Service: Cloudflare
- Hostname: nashville.mervinhernandez.com (the full FQDN)
- Username: [your Cloudflare email — or "Bearer" depending on UDM firmware]
- Password: [the API token from Step 2a]
```

> **Note on credentials format:** The UDM Pro's Cloudflare DDNS integration may use the API token directly in the password field with your Cloudflare email as username. If it doesn't work, try username = `Bearer` and password = the API token. Check the UniFi community for the exact format your firmware version (10.1.85) expects.
>

The UDM Pro will now automatically update the Cloudflare DNS record whenever the WAN IP changes.

- [x]  DDNS configured on UDM Pro with Cloudflare
- [x]  Verify it's working: confirmed `nslookup nashville.mervinhernandez.com` resolves to `68.84.90.8` from external server (spin5)
- [x]  Note DDNS hostname: `nashville.mervinhernandez.com`

---

## Phase 3: Nashville — Configure WireGuard Server on UDM Pro

The UDM Pro acts as the WireGuard server. Both Orlando sites will connect to it as clients.

### ✅ Step 3a — Create WireGuard Server

```
Settings > VPN > VPN Server > Create New
- Protocol: WireGuard
- Name: Nashville-WG-Server
- Port: 51820 (default, or choose another)
- Server Address: 10.20.0.1/24 (tunnel network — not the LAN)
- DNS: 1.1.1.1 (or your preferred DNS)
```

- [x]  WireGuard server created on UDM Pro: `WingManWG`
- [x]  Note server port: `51820`
- [x]  Note server tunnel IP: `10.20.0.1/24` (Advanced > Manual > Gateway/Subnet confirmed)

### ✅ Step 3b — Firewall: Allow WireGuard inbound on WAN

The UDM Pro should auto-create a firewall rule for the WireGuard port, but verify:

```
Settings > Firewall & Security > Firewall Rules > WAN tab
- Confirm a rule exists allowing UDP traffic on port 51820 (or your chosen port) inbound
- If not, create one:
    Name: Allow WireGuard
    Action: Allow
    Protocol: UDP
    Destination Port: 51820
    Source: Any
```

- [x]  Firewall rule auto-created by UDM Pro: "Allow WireGuard Server" — Accept, Internet Local, UDP, port 51820

###  ⏳Step 3b1 - Individual Remote Client
My WingManUDM is located in Nashville and seems to be correctly configured to allow connections to wireguard. 
I am presently located in Wisconsin. I want to connect just my laptop to the UDM wireguard, and route my YouTube TV traffic as a test of my wireguard. 
Give me the specific steps for connecting just my laptop directly to the UDM via wireguard, and for my YouTube TV traffic to go to Nashville and back to my laptop. 

### ⏳ Step 3c — Create Client Configurations

Create two client profiles — one for each Orlando site.

**Client 1: Anders Way**

```
Settings > VPN > VPN Server > Nashville-WG-Server > Add Client
- Name: AndersWay-Client
- Tunnel IP: 10.20.0.2 (auto-assigned or manual)
- Download / copy the client configuration
```

**Client 2: Hardwood House**

```
Settings > VPN > VPN Server > Nashville-WG-Server > Add Client
- Name: HardwoodHouse-Client
- Tunnel IP: 10.20.0.3 (auto-assigned or manual)
- Download / copy the client configuration
```

> The client config will include: server public key, client private key, endpoint (use your DDNS hostname + port here), and allowed IPs. Modify the `Endpoint` to use the DDNS hostname instead of a raw IP.
>
- [ ]  Anders Way client config created — tunnel IP: `10.20.0.2`
- [ ]  Hardwood House client config created — tunnel IP: `10.20.0.3`
- [ ]  Both configs use DDNS hostname as endpoint (not raw IP)
- [ ]  Client configs saved securely for use in Phases 4 and 5

### ⏳ Step 3d — Enable NAT / Masquerade for tunnel traffic

Traffic arriving from the WireGuard tunnel needs to be NATted to the UDM Pro's WAN IP so it can reach the internet (and YouTube TV sees a Nashville IP).

On UniFi 10.x, the UDM Pro should automatically NAT traffic from VPN clients destined for the internet. Verify:

```
Settings > Routing > NAT
- Confirm masquerade is enabled for WAN (this is typically on by default)
```

If YouTube TV still shows the wrong market after testing (Phase 9), you may need a custom NAT rule:

```
Settings > Routing > NAT > Create New Rule
- Name: NAT-WG-Clients
- Type: Masquerade
- Source: 10.20.0.0/24
- Outbound Interface: WAN
```

- [ ]  NAT / masquerade confirmed for WireGuard client traffic exiting WAN

---

## Phase 4: Anders Way — Create AppleTV VLAN + WireGuard Client

### Step 4a — Create AppleTV VLAN

```
Settings > Networks > Create New Network
- Name: AppleTV
- VLAN ID: 50  (confirm unused)
- Gateway IP / Subnet: 192.168.50.1/24
- DHCP: Enabled
- DHCP Range: 192.168.50.100 – 192.168.50.200
```

- [ ]  AppleTV VLAN created on Anders Way
- [ ]  VLAN ID confirmed unused: 50

### Step 4b — Create AppleTV WiFi SSID (optional but recommended)

```
Settings > WiFi > Create New
- Name: AppleTV-Nash (or a hidden SSID)
- Network: AppleTV (VLAN 50)
- Security: WPA2/WPA3
- Password: [choose]
```

> Mobile devices can join this SSID when they want Nashville routing for YouTube TV, and use the normal SSID otherwise.
>
- [ ]  AppleTV WiFi SSID created

### Step 4c — Configure WireGuard VPN Client

```
Settings > VPN > VPN Client > Create New
- Protocol: WireGuard
- Name: Nashville-Tunnel
- Configuration: Paste or import the Anders Way client config from Phase 3c
  - Ensure Endpoint uses DDNS hostname
  - Ensure AllowedIPs = 0.0.0.0/0 (send all tunnel-routed traffic to Nashville)
```

- [ ]  WireGuard VPN client configured on Anders Way UCG Max
- [ ]  Tunnel status shows Connected (Settings > VPN)

### Step 4d — Policy-Based Routing: Route AppleTV VLAN through tunnel

This is the critical step — it tells the UCG Max to send all traffic from the AppleTV VLAN through the WireGuard tunnel instead of the local WAN.

```
Settings > Routing > Policy-Based Routes > Create New
- Name: AppleTV-via-Nashville
- Source: AppleTV network (192.168.50.0/24)
- Destination: Any (0.0.0.0/0)
- Interface: Nashville-Tunnel (the WireGuard VPN client)
```

> **Important:** This only affects the AppleTV VLAN. The Anders Way default network (192.168.1.0/24) is completely unaffected.
>
- [ ]  Policy-based route created: AppleTV VLAN > Nashville tunnel
- [ ]  Default network traffic confirmed unaffected (test from a default-network device)

---

## Phase 5: Hardwood House — Create AppleTV VLAN + WireGuard Client

> **Prerequisite:** Confirm from Phase 1 that WireGuard VPN Client is available on the UX firmware (9.0.114). If not, see the firmware note in Phase 1 and resolve before continuing.
>

### Step 5a — Create AppleTV VLAN

```
Settings > Networks > Create New Network
- Name: AppleTV
- VLAN ID: 50  (confirm unused)
- Gateway IP / Subnet: 192.168.50.1/24
- DHCP: Enabled
- DHCP Range: 192.168.50.100 – 192.168.50.200
```

- [ ]  AppleTV VLAN created on Hardwood House
- [ ]  VLAN ID confirmed unused: 50

### Step 5b — Create AppleTV WiFi SSID (optional but recommended)

```
Settings > WiFi > Create New
- Name: AppleTV-Nash (or a hidden SSID)
- Network: AppleTV (VLAN 50)
- Security: WPA2/WPA3
- Password: [choose]
```

- [ ]  AppleTV WiFi SSID created

### Step 5c — Configure WireGuard VPN Client

```
Settings > VPN > VPN Client > Create New
- Protocol: WireGuard
- Name: Nashville-Tunnel
- Configuration: Paste or import the Hardwood House client config from Phase 3c
  - Ensure Endpoint uses DDNS hostname
  - Ensure AllowedIPs = 0.0.0.0/0
```

- [ ]  WireGuard VPN client configured on Hardwood House UX
- [ ]  Tunnel status shows Connected (Settings > VPN)

### Step 5d — Policy-Based Routing: Route AppleTV VLAN through tunnel

```
Settings > Routing > Policy-Based Routes > Create New
- Name: AppleTV-via-Nashville
- Source: AppleTV network (192.168.50.0/24)
- Destination: Any (0.0.0.0/0)
- Interface: Nashville-Tunnel (the WireGuard VPN client)
```

- [ ]  Policy-based route created: AppleTV VLAN > Nashville tunnel
- [ ]  Default network traffic confirmed unaffected

---

## Phase 6: Verify Tunnels

### Anders Way

- [ ]  Settings > VPN > VPN Client — Nashville-Tunnel shows **Connected**
- [ ]  Assign a test device (laptop) to the AppleTV VLAN (192.168.50.x)
- [ ]  From test device: visit [whatismyip.com](http://whatismyip.com/) — should show **Nashville WAN IP**
- [ ]  From a default-network device: visit [whatismyip.com](http://whatismyip.com/) — should show **Anders Way WAN IP** (unchanged)

### Hardwood House

- [ ]  Settings > VPN > VPN Client — Nashville-Tunnel shows **Connected**
- [ ]  Assign a test device (laptop) to the AppleTV VLAN (192.168.50.x)
- [ ]  From test device: visit [whatismyip.com](http://whatismyip.com/) — should show **Nashville WAN IP**
- [ ]  From a default-network device: visit [whatismyip.com](http://whatismyip.com/) — should show **Hardwood House WAN IP** (unchanged)

### Nashville

- [ ]  Settings > VPN > VPN Server — both clients show connected
- [ ]  Verify no unexpected traffic on Nashville LAN (tunnel traffic should NAT out WAN, not leak to LAN)

---

## Phase 7: NAT Verification — Nashville

If Phase 6 test devices show Nashville WAN IP on [whatismyip.com](http://whatismyip.com/), NAT is working correctly. If not:

- [ ]  Check Settings > Routing > NAT — masquerade should be enabled for WAN
- [ ]  If needed, create a manual masquerade rule for source 10.20.0.0/24 out WAN (see Phase 3d)
- [ ]  Re-test from an AppleTV VLAN device — [whatismyip.com](http://whatismyip.com/) must show Nashville IP

---

## Phase 8: Assign Devices to AppleTV VLANs

### Anders Way — Apple TV

**If wired:**

```
UniFi Network > Ports > [port Apple TV is on]
- Port Profile: AppleTV (VLAN 50)
```

**If wireless:**
Connect Apple TV to the AppleTV-Nash SSID created in Step 4b.

- [ ]  Anders Way Apple TV on AppleTV VLAN
- [ ]  Apple TV receives IP in 192.168.50.x range

### Hardwood House — Apple TV

**If wired:**

```
UniFi Network > Ports > [port Apple TV is on]
- Port Profile: AppleTV (VLAN 50)
```

**If wireless:**
Connect Apple TV to the AppleTV-Nash SSID created in Step 5b.

- [ ]  Hardwood House Apple TV on AppleTV VLAN
- [ ]  Apple TV receives IP in 192.168.50.x range

### Mobile Devices

> Mobile devices can switch to the AppleTV-Nash SSID when they want to watch YouTube TV with Nashville market, and use the normal SSID for everything else. No permanent assignment needed.
>

---

## Phase 9: Test & Validate

### Anders Way

- [ ]  On Apple TV: open YouTube TV > Settings > Area — confirm shows **Nashville** market
- [ ]  On Apple TV: [whatismyip.com](http://whatismyip.com/) (via browser or app) shows Nashville IP
- [ ]  Test a YouTube TV live stream — confirm playback quality is acceptable
- [ ]  On a default-network device: confirm WAN IP still shows Anders Way / Orlando IP
- [ ]  On a mobile device connected to AppleTV-Nash SSID: confirm Nashville market in YouTube TV

### Hardwood House

- [ ]  On Apple TV: open YouTube TV > Settings > Area — confirm shows **Nashville** market
- [ ]  On Apple TV: [whatismyip.com](http://whatismyip.com/) shows Nashville IP
- [ ]  Test a YouTube TV live stream — confirm playback quality
- [ ]  On a default-network device: confirm WAN IP still shows Hardwood House / Orlando IP
- [ ]  On a mobile device connected to AppleTV-Nash SSID: confirm Nashville market in YouTube TV

### Performance Baseline

- [ ]  Run speed test from an AppleTV VLAN device at each site — note download/upload/latency
- [ ]  Expected: ~20-40ms added latency (Orlando <> Nashville round trip)
- [ ]  YouTube TV uses ~13-20 Mbps per stream — confirm Nashville upload can handle concurrent streams from both sites

---

## Ongoing Considerations

| Item | Note |
| --- | --- |
| **DDNS** | UDM Pro auto-updates DDNS record on WAN IP change. Tunnels reconnect automatically using the hostname. |
| **Bandwidth** | All YouTube TV streams traverse Nashville WAN. Two sites streaming simultaneously = 2x bandwidth. Monitor Nashville upload capacity. |
| **Hardwood House firmware** | If UX needs to stay on 9.0.114, WireGuard may require an alternative approach (see Phase 1 note). |
| **Adding more devices** | Any device on the AppleTV VLAN (VLAN 50) automatically routes through Nashville. Just assign it to the VLAN or connect to the AppleTV-Nash SSID. |
| **Tunnel monitoring** | Check VPN status on each console periodically. If a tunnel drops, DDNS hostname change or firewall issue is the likely cause. |
| **YouTube TV home area** | YouTube TV requires you to check in from your "home area" periodically. Using Nashville as the tunnel exit keeps you in the Nashville market. Ensure at least one Nashville device checks in occasionally. |

---

## Rollback Plan

If anything goes wrong at any phase, rollback is straightforward:

| To undo... | Do this |
| --- | --- |
| Policy-based route | Delete the route in Settings > Routing > Policy-Based Routes |
| WireGuard client | Disconnect and delete in Settings > VPN > VPN Client |
| AppleTV VLAN | Move devices back to default network, then delete the VLAN |
| WireGuard server (Nashville) | Delete in Settings > VPN > VPN Server |
| DDNS | Disable in Settings > Internet > WAN > Dynamic DNS |

All changes are made through the UniFi UI — no SSH, no boot scripts, no manual iptables rules to track.

---

## Status Tracker

| Phase | Status | Notes |
| --- | --- | --- |
| Phase 1: Pre-flight checks | Not started | All three sites need verification |
| Phase 2: Nashville Cloudflare DDNS | **Complete** | [nashville.mervinhernandez.com](http://nashville.mervinhernandez.com/) → 68.84.90.8 |
| Phase 3: Nashville WireGuard Server | Not started | Two client configs needed (one per Orlando site) |
| Phase 4: Anders Way VLAN + WireGuard Client | Not started |  |
| Phase 5: Hardwood House VLAN + WireGuard Client | Not started | Firmware compatibility TBD |
| Phase 6: Tunnel verification | Not started |  |
| Phase 7: NAT verification | Not started |  |
| Phase 8: Device assignment | Not started |  |
| Phase 9: Testing | Not started |  |