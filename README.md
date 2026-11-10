**English** | [Русский](README.ru.md)

# phone-multiwan

**Get the full carrier speed out of a single 5G phone when every tethering method hits its own ceiling.**

The phone gets ~450 Mbit/s from the carrier, but no single tethering method can pass that on: USB tethering is capped by USB 2.0 (~300), the phone's Wi‑Fi hotspot by the airtime all its clients share (~145–160 in total), and the router by its 100 Mbit/s ports (~98). As long as the sum of these ceilings is below the cellular speed, the links **add up**. This repository is a small Linux service that spreads connections across all links from the same phone at once.

| Setup | Speedtest, download |
|---|---|
| Router only | 96–98 Mbit/s |
| USB tethering + router | 396 Mbit/s |
| **USB tethering + router + Wi‑Fi adapter** | **456 Mbit/s** (upload 48) |

Full write-up with measurements (in Russian): [docs/article.ru.md](docs/article.ru.md).

## How it works

```
                   ┌── USB cable, USB tethering ──────────────────── ~300 ──┐
 5G ~450 ──► phone ├── Wi‑Fi ──► router (WISP) ──► LAN cable ──────── ~98 ──┼──► Linux: ECMP ──► apps
                   └── Wi‑Fi ──► USB Wi‑Fi adapter ────────────────── ~50 ──┘
```

- The system gets one default route with several next hops (ECMP). Hashing on addresses and ports (`fib_multipath_hash_policy=1`) spreads **connections** across the links: each connection stays on one link, while a multi-stream download uses all of them.
- All links reach the internet through the same phone, so every connection has the same public IP and websites don't see you "jumping" between addresses.
- Every 5 seconds the service checks internet access through each link, drops a dead one and brings it back once it recovers. Its route sits above NetworkManager's routes (metric 50) and is removed when the service stops, so everything goes back to how it was.
- If the phone is carried away and brought back, the Wi‑Fi adapter often reconnects at the edge of coverage and stays at a low rate. The service notices this and reconnects the adapter once when the signal is good again.

## Requirements

- Linux with **NetworkManager**, `iproute2`, `iw`, `ping`, systemd.
- A phone in **USB tethering** mode: Android (drivers `rndis_host`, `cdc_ncm`, `cdc_ether`) or iPhone (`ipheth`).
- A second and/or third link from the same phone: **LAN** (a router that takes internet from the phone's hotspot) and/or a **Wi‑Fi adapter** connected directly to the phone's hotspot. Works with any combination of two or three links.

## Installation

```bash
git clone https://github.com/byha78/phone-multiwan.git
cd phone-multiwan
sudo bash install.sh
```

The installer copies the service to `/usr/local/sbin`, enables it at boot and sets two kernel options (`/etc/sysctl.d/90-multiwan.conf`).

**NetworkManager setup (recommended):**

```bash
# disable IPv6 on the USB tethering and Wi-Fi adapter connections, otherwise IPv6 traffic bypasses the balancing
nmcli con modify "<USB tethering profile>"   ipv6.method disabled
nmcli con modify "<Wi-Fi adapter profile>"   ipv6.method disabled
# give LAN a higher priority than Wi-Fi, in case the service stops
nmcli con modify "<LAN profile>" ipv4.route-metric 500
```

## Checking

```bash
journalctl -u multiwan-balance -f      # "Active: USB, LAN, Wi-Fi"
ip route show default proto 99         # the shared route and link weights
```

## Configuration

**Interfaces are detected automatically:**
- **USB tethering:** by driver, from `USB_DRIVERS`;
- **LAN:** the first wired interface with a gateway that is not the USB tethering one. Works with both a physical NIC and a VM's virtual NIC;
- **Wi‑Fi:** the first wireless interface.

If you have a USB network card using the `cdc_ether` driver, the service may mistake it for the phone. In that case, set the tethering interface explicitly with `USB_IF`.

**Any parameter** can be set without editing the script:

```bash
sudo systemctl edit multiwan-balance
```
```ini
[Service]
Environment=WIFI_MODE=reserve
Environment=USB_WEIGHT=3
```

| Parameter | Default | What it does |
|---|---|---|
| `USB_IF` / `LAN_IF` / `WIFI_IF` | auto-detected | set the link interfaces explicitly |
| `USB_DRIVERS` | `rndis_host cdc_ncm cdc_ether ipheth` | drivers used to find the USB tethering interface |
| `WIFI_MODE` | `balance` | `balance`: Wi‑Fi is the third link; `reserve`: used only when USB and LAN are both down |
| `USB_WEIGHT` / `LAN_WEIGHT` / `WIFI_WEIGHT` | 2 / 1 / 1 | share of new connections on each link |
| `TARGETS` | `1.1.1.1 8.8.8.8` | hosts pinged to check a link |
| `PING_TIMEOUT` | 4 | seconds to wait for a reply: latency through a loaded phone can be high |
| `INTERVAL` | 5 | check interval, seconds |
| `FAILS_TO_DOWN` | 3 | failed checks in a row before a link is dropped |
| `REFRESH_SIGNAL` | −60 | signal (dBm) at which a returned Wi‑Fi adapter is reconnected |
| `REFRESH_CHECKS` | 3 | good checks in a row before reconnecting |

**`WIFI_MODE`:** with Wi‑Fi in the balance, download is at its maximum but upload is slightly lower: the links compete for the same cellular uplink and the same Wi‑Fi airtime. If upload matters more, use `reserve`.

## Uninstalling

```bash
sudo systemctl disable --now multiwan-balance
sudo rm /usr/local/sbin/multiwan-balance /etc/systemd/system/multiwan-balance.service /etc/sysctl.d/90-multiwan.conf
```

## Limitations

- **Upload doesn't add up.** It is limited by the cellular uplink (~30–57 Mbit/s in the author's case), and splitting it across links even hurts a little.
- **A single download** uses one link, so it is capped at that link's speed (~300 over USB).
- USB and Wi‑Fi tethering share one cellular connection, so the total can't exceed its speed.
- If the router is on but has lost the phone, the service notices within ~15–40 seconds.

## License

[MIT](LICENSE)
