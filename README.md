# netmanager

A menu-driven Bash script for managing networks and DNS on Linux, built on top of NetworkManager (`nmcli`).

## Features

### 1. Networks
- Scan for available Wi-Fi networks, sorted by signal strength, with security type shown
- Connect to the network you pick (reuses a saved profile when one exists, asks for a password only when needed)
- Show active connections, disconnect, forget a saved network, toggle the Wi-Fi radio

### 2. DNS
- Change DNS for any active connection using:
  - a public provider: Cloudflare (standard and malware-blocking), Google, Quad9, OpenDNS, AdGuard, CleanBrowsing (family), Control D
  - custom servers (IPv4 and/or IPv6, with basic validation)
  - reset to automatic (DHCP)
- Show the current DNS servers
- Benchmark the public providers by response time

### 3. Network tools
- Interfaces, IP addresses and default gateway
- Ping and traceroute (`mtr`, `traceroute` or `tracepath`, whichever is installed)
- DNS lookup with a custom record type and DNS server
- Public IP with whois info
- Quick connectivity diagnosis (gateway, internet, DNS, HTTPS)
- Listening ports and remote port check
- Whois lookup
- DNS cache flush
- Download speed test
- ARP / neighbor table
- Local network scan (nmap)
- Restart NetworkManager

## Requirements

- Linux with NetworkManager running (needed for options 1 and 2)
- `bash` 4+, `iproute2` (`ip`, `ss`), `curl`
- Optional, for specific tools:
  - `dig` (package `dnsutils` or `bind-utils`) for DNS lookup and benchmark
  - `mtr` / `traceroute` for route tracing
  - `nmap` for the network scan
  - `whois` for whois lookups
  - `nc` (netcat) for the port check

Install NetworkManager if it is missing:

```bash
# Debian / Ubuntu
sudo apt install network-manager
# Fedora / RHEL
sudo dnf install NetworkManager
# Arch
sudo pacman -S networkmanager
```

## Usage

### Run directly from GitHub

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/RedemptionMHA/netmanager/main/netmanager.sh)
```

Piping into bash also works, because the script reconnects to your terminal for the menus:

```bash
curl -fsSL https://raw.githubusercontent.com/RedemptionMHA/netmanager/main/netmanager.sh | bash
```

To pin a specific release instead of the latest `main`, replace `main` in the URL with a tag, for example `v1.0`.

> **Read before running:** this runs code from the internet as your user, and the script calls `sudo` for some actions. Review [`netmanager.sh`](netmanager.sh) first if you want to know exactly what it does.

### Add a shortcut to bash

Create a `netmanager` command that always runs the latest version from GitHub:

```bash
echo "alias netmanager='bash <(curl -fsSL https://raw.githubusercontent.com/RedemptionMHA/netmanager/main/netmanager.sh)'" >> ~/.bashrc
source ~/.bashrc
```

Then just type `netmanager` in any terminal. For zsh, use `~/.zshrc` instead of `~/.bashrc`.

Or install it as a real command that works offline:

```bash
sudo curl -fsSL https://raw.githubusercontent.com/RedemptionMHA/netmanager/main/netmanager.sh -o /usr/local/bin/netmanager
sudo chmod +x /usr/local/bin/netmanager
```

Re-run the `curl` line to update it later.

### Run a local copy

```bash
git clone https://github.com/RedemptionMHA/netmanager.git
cd netmanager
chmod +x netmanager.sh
./netmanager.sh
```

The script asks for `sudo` only when an action needs it, so you do not need to start it as root.

## Notes

- DNS changes are applied per NetworkManager connection and take effect after the connection is re-activated (the script does this for you).
- Choosing "Reset to automatic" restores the DNS servers handed out by your router/DHCP.
- Hidden Wi-Fi networks are not listed in the scan.

## License

MIT
