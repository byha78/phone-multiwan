**English** | [Русский](README.ru.md)

# phone-multiwan

A Linux service that spreads connections across several ways of sharing internet from one phone at the same time:

- **USB cable**: the phone in USB tethering mode;
- **LAN**: a router that takes internet from the phone's hotspot;
- **Wi‑Fi adapter**: connected directly to the phone's hotspot.

Why: every tethering method has its own ceiling. USB 2.0 + RNDIS gives ~300 Mbit/s, the phone's Wi‑Fi hotspot ~145–160 for all clients together, a router with 10/100 ports ~98. The cellular network can deliver more than any of them. In the author's case the 5G phone got ~450 Mbit/s: through the router alone the computer saw 96–98, through all three links 456 in speedtest.

Full write-up with measurements (in Russian): [article on Habr](https://habr.com/ru/articles/1105562/), copy in this repo: [docs/article.ru.md](docs/article.ru.md).

## How it works

```
                   ┌── USB cable, USB tethering ──────────────────── ~300 ──┐
 5G ~450 ──► phone ├── Wi‑Fi ──► router (WISP) ──► LAN cable ──────── ~98 ──┼──► Linux: ECMP ──► apps
                   └── Wi‑Fi ──► USB Wi‑Fi adapter ────────────────── ~50 ──┘
```

- Sets one default route with several next hops (ECMP). Hashing on addresses and ports spreads **connections** across the links: one connection stays on one link, a multi-stream download uses all of them.
- Every 5 seconds checks internet access through each link, drops a dead one and brings it back once it recovers.
- Its route sits above NetworkManager's routes and is removed when the service stops.
- If the Wi‑Fi adapter gets stuck at a low rate after the phone comes back, reconnects it once.

## Requirements

- Linux with **NetworkManager**, `iproute2`, `iw`, `ping`, systemd.
- A phone in **USB tethering** mode: Android (`rndis_host`, `cdc_ncm`, `cdc_ether`) or iPhone (`ipheth`).
- At least one more link from the same phone: LAN through a router and/or a Wi‑Fi adapter. Works with any combination of two or three links.

## Installation

```bash
git clone https://github.com/byha78/phone-multiwan.git
cd phone-multiwan
sudo bash install.sh
```

The installer copies the service to `/usr/local/sbin`, enables it at boot and sets two kernel options in `/etc/sysctl.d/90-multiwan.conf`.

Recommended NetworkManager setup:

```bash
# otherwise IPv6 traffic bypasses the balancing
nmcli con modify "<USB tethering profile>" ipv6.method disabled
nmcli con modify "<Wi-Fi adapter profile>" ipv6.method disabled
# LAN takes priority over Wi-Fi if the service is stopped
nmcli con modify "<LAN profile>" ipv4.route-metric 500
```

## Checking

```bash
journalctl -u multiwan-balance -f      # "Active: USB, LAN, Wi-Fi"
ip route show default proto 99         # the shared route and link weights
```

## Configuration

Interfaces are detected automatically: USB tethering by driver, LAN as the first wired interface with a gateway, Wi‑Fi as the first wireless one. If a USB network card using `cdc_ether` is mistaken for the phone, set `USB_IF` explicitly.

Parameters can be set without editing the script:

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
| `USB_IF` / `LAN_IF` / `WIFI_IF` | auto-detected | set the interfaces explicitly |
| `USB_DRIVERS` | `rndis_host cdc_ncm cdc_ether ipheth` | drivers used to find USB tethering |
| `WIFI_MODE` | `balance` | `balance`: Wi‑Fi is the third link; `reserve`: used only when USB and LAN are down |
| `USB_WEIGHT` / `LAN_WEIGHT` / `WIFI_WEIGHT` | 2 / 1 / 1 | share of new connections per link |
| `TARGETS` | `1.1.1.1 8.8.8.8` | hosts pinged to check a link |
| `PING_TIMEOUT` | 4 | seconds to wait for a reply |
| `INTERVAL` | 5 | check interval, seconds |
| `FAILS_TO_DOWN` | 3 | failed checks in a row before a link is dropped |
| `REFRESH_SIGNAL` | −60 | signal (dBm) at which a returned Wi‑Fi adapter is reconnected |
| `REFRESH_CHECKS` | 3 | good checks in a row before reconnecting |

With Wi‑Fi in the balance, download is at its maximum but upload is slightly lower. If upload matters more, use `WIFI_MODE=reserve`.

## Uninstalling

```bash
sudo systemctl disable --now multiwan-balance
sudo rm /usr/local/sbin/multiwan-balance /etc/systemd/system/multiwan-balance.service /etc/sysctl.d/90-multiwan.conf
```

## Limitations

- Multi-stream downloads add up. A single connection is limited to its link.
- Upload doesn't add up: the cellular uplink limits it.
- The total can't exceed the cellular network speed.

## License

[MIT](LICENSE)
