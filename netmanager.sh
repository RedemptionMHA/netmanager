#!/usr/bin/env bash
#
# netmanager.sh - Network & DNS manager (NetworkManager / nmcli based)
#
#   1) Wi-Fi: scan, list and connect to a network
#   2) DNS:   change DNS per connection (public providers, custom, or reset)
#   3) Tools: common networking utilities
#
# Usage: ./netmanager.sh        (sudo is requested automatically when needed)

set -u

# ---------- colors ----------
if [[ -t 1 ]]; then
    R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; C=$'\e[36m'; W=$'\e[1m'; N=$'\e[0m'
else
    R=""; G=""; Y=""; B=""; C=""; W=""; N=""
fi

info()  { echo "${C}[*]${N} $*"; }
ok()    { echo "${G}[+]${N} $*"; }
warn()  { echo "${Y}[!]${N} $*"; }
err()   { echo "${R}[-]${N} $*" >&2; }
pause() { echo; read -rp "Press Enter to continue..." _; }
have()  { command -v "$1" >/dev/null 2>&1; }

SUDO=""
if [[ $EUID -ne 0 ]]; then
    if have sudo; then SUDO="sudo"; else warn "Not root and sudo not found; some actions may fail."; fi
fi

# ---------- public DNS providers: "Name|IPv4 list|IPv6 list" ----------
DNS_PROVIDERS=(
    "Cloudflare|1.1.1.1,1.0.0.1|2606:4700:4700::1111,2606:4700:4700::1001"
    "Cloudflare (malware blocking)|1.1.1.2,1.0.0.2|2606:4700:4700::1112,2606:4700:4700::1002"
    "Google|8.8.8.8,8.8.4.4|2001:4860:4860::8888,2001:4860:4860::8844"
    "Quad9|9.9.9.9,149.112.112.112|2620:fe::fe,2620:fe::9"
    "OpenDNS|208.67.222.222,208.67.220.220|2620:119:35::35,2620:119:53::53"
    "AdGuard (ad blocking)|94.140.14.14,94.140.15.15|2a10:50c0::ad1:ff,2a10:50c0::ad2:ff"
    "CleanBrowsing (family)|185.228.168.168,185.228.169.168|2a0d:2a00:1::,2a0d:2a00:2::"
    "Control D|76.76.2.0,76.76.10.0|2606:1a40::,2606:1a40:1::"
)

# ---------- dependency checks ----------
need_nmcli() {
    if ! have nmcli; then
        err "nmcli (NetworkManager) is required for this option."
        echo "    Debian/Ubuntu: sudo apt install network-manager"
        echo "    Fedora/RHEL:   sudo dnf install NetworkManager"
        echo "    Arch:          sudo pacman -S networkmanager"
        return 1
    fi
    if ! nmcli -t general status >/dev/null 2>&1; then
        err "NetworkManager is not running (try: sudo systemctl start NetworkManager)."
        return 1
    fi
    return 0
}

# Show a numbered menu from an array (global: PICK holds the chosen index, 0-based)
# usage: choose "prompt" "${items[@]}"
choose() {
    local prompt="$1"; shift
    local items=("$@") i
    PICK=-1
    for i in "${!items[@]}"; do
        printf "  %s%2d)%s %s\n" "$W" $((i + 1)) "$N" "${items[$i]}"
    done
    echo "   ${W} 0)${N} Cancel"
    local n
    while true; do
        read -rp "$prompt " n
        [[ "$n" == "0" ]] && return 1
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#items[@]} )); then
            PICK=$((n - 1)); return 0
        fi
        warn "Invalid choice."
    done
}

###############################################################################
# 1) WI-FI
###############################################################################
wifi_iface() {
    nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}'
}

wifi_connect() {
    need_nmcli || return
    local iface; iface=$(wifi_iface)
    if [[ -z "$iface" ]]; then err "No Wi-Fi interface found."; return; fi

    if [[ "$(nmcli radio wifi)" != "enabled" ]]; then
        warn "Wi-Fi radio is off. Turning it on..."
        $SUDO nmcli radio wifi on; sleep 2
    fi

    info "Scanning on ${W}$iface${N} ..."
    nmcli device wifi rescan ifname "$iface" >/dev/null 2>&1
    sleep 3

    local line inuse ssid signal sec
    local -a ssids=() labels=() seen=()
    declare -A seen_ssid=()
    while IFS= read -r line; do
        line=${line//\\:/§}                       # protect escaped colons in SSIDs
        IFS=: read -r inuse ssid signal sec <<<"$line"
        ssid=${ssid//§/:}
        [[ -z "$ssid" ]] && continue               # skip hidden networks
        [[ -n "${seen_ssid[$ssid]:-}" ]] && continue
        seen_ssid[$ssid]=1
        [[ -z "$sec" ]] && sec="open"
        local mark=" "; [[ "$inuse" == "*" ]] && mark="${G}*${N}"
        ssids+=("$ssid")
        labels+=("$(printf "%s %-32s signal:%3s%%  %s" "$mark" "$ssid" "$signal" "$sec")")
    done < <(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list ifname "$iface" | sort -t: -k3 -nr)

    if (( ${#ssids[@]} == 0 )); then warn "No networks found."; return; fi

    echo; echo "${W}Available networks${N} (* = connected)"
    choose "Select network:" "${labels[@]}" || return
    local target="${ssids[$PICK]}"

    # Already a saved profile?
    if nmcli -t -f NAME connection show | grep -Fxq "$target"; then
        info "Saved profile found for '$target', connecting..."
        if $SUDO nmcli connection up "$target" ifname "$iface"; then ok "Connected to $target"; return; fi
        warn "Saved profile failed (maybe the password changed)."
        read -rp "Delete the saved profile and re-enter password? [y/N] " a
        [[ "$a" =~ ^[Yy]$ ]] && $SUDO nmcli connection delete "$target" >/dev/null || return
    fi

    local pw=""
    if [[ "${labels[$PICK]}" != *open* ]]; then
        read -rsp "Password for '$target': " pw; echo
    fi

    info "Connecting to '$target' ..."
    if [[ -n "$pw" ]]; then
        $SUDO nmcli device wifi connect "$target" password "$pw" ifname "$iface"
    else
        $SUDO nmcli device wifi connect "$target" ifname "$iface"
    fi && ok "Connected to $target" || err "Connection failed."
}

wifi_other() {
    need_nmcli || return
    local opts=("Show active connections" "Disconnect Wi-Fi" "Forget a saved network" "Toggle Wi-Fi radio")
    choose "Select:" "${opts[@]}" || return
    case $PICK in
        0) nmcli -f NAME,TYPE,DEVICE connection show --active ;;
        1) local i; i=$(wifi_iface); $SUDO nmcli device disconnect "$i" && ok "Disconnected." ;;
        2)
            mapfile -t saved < <(nmcli -t -f NAME,TYPE connection show | awk -F: '$2 ~ /wireless/{print $1}')
            (( ${#saved[@]} )) || { warn "No saved Wi-Fi profiles."; return; }
            choose "Forget which?" "${saved[@]}" && $SUDO nmcli connection delete "${saved[$PICK]}"
            ;;
        3)
            if [[ "$(nmcli radio wifi)" == "enabled" ]]; then $SUDO nmcli radio wifi off && ok "Wi-Fi off"
            else $SUDO nmcli radio wifi on && ok "Wi-Fi on"; fi
            ;;
    esac
}

menu_wifi() {
    while true; do
        clear
        echo "${W}=== Wi-Fi / Networks ===${N}"
        echo "  1) Scan and connect to a network"
        echo "  2) Other (status, disconnect, forget, radio on/off)"
        echo "  0) Back"
        read -rp "> " c
        case $c in
            1) wifi_connect; pause ;;
            2) wifi_other; pause ;;
            0) return ;;
        esac
    done
}

###############################################################################
# 2) DNS
###############################################################################
valid_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS=.; local -a o=($ip)
        for x in "${o[@]}"; do (( x <= 255 )) || return 1; done
        return 0
    fi
    [[ $ip =~ ^[0-9a-fA-F:]+$ && $ip == *:* ]]    # loose IPv6 check
}

show_current_dns() {
    echo "${W}Current DNS servers:${N}"
    if have resolvectl && resolvectl status >/dev/null 2>&1; then
        resolvectl dns
    else
        grep -E '^nameserver' /etc/resolv.conf 2>/dev/null || echo "  (none found)"
    fi
}

# apply_dns <connection> <ipv4 csv> <ipv6 csv>  (empty = reset to automatic)
apply_dns() {
    local con=$1 v4=$2 v6=$3
    if [[ -z "$v4" && -z "$v6" ]]; then
        $SUDO nmcli connection modify "$con" ipv4.ignore-auto-dns no ipv4.dns "" \
                                             ipv6.ignore-auto-dns no ipv6.dns ""
    else
        $SUDO nmcli connection modify "$con" \
            ipv4.ignore-auto-dns yes ipv4.dns "$v4" \
            ipv6.ignore-auto-dns "$([[ -n $v6 ]] && echo yes || echo no)" ipv6.dns "$v6" || return 1
    fi
    info "Re-activating '$con' to apply changes..."
    $SUDO nmcli connection up "$con" >/dev/null && ok "Done." || err "Failed to re-activate connection."
}

dns_change() {
    need_nmcli || return

    # Pick connection
    local -a names=() labels=()
    local name dev type
    while IFS=: read -r name type dev; do
        [[ "$type" == "loopback" || "$type" == "bridge" || "$type" == "tun" || "$name" == docker* ]] && continue
        names+=("$name"); labels+=("$name  [$type on ${dev:-?}]")
    done < <(nmcli -t -f NAME,TYPE,DEVICE connection show --active)

    (( ${#names[@]} )) || { err "No active connections. Connect to a network first."; return; }
    echo "${W}Select the connection to modify:${N}"
    choose "Connection:" "${labels[@]}" || return
    local con="${names[$PICK]}"

    echo; show_current_dns; echo
    echo "${W}DNS options for '$con':${N}"
    local -a popts=() p
    for p in "${DNS_PROVIDERS[@]}"; do
        IFS='|' read -r pn pv4 pv6 <<<"$p"
        popts+=("$(printf "%-30s %s" "$pn" "${pv4//,/ , }")")
    done
    popts+=("Custom DNS servers" "Reset to automatic (DHCP)")
    choose "Select:" "${popts[@]}" || return

    local v4="" v6=""
    if (( PICK < ${#DNS_PROVIDERS[@]} )); then
        IFS='|' read -r pn v4 v6 <<<"${DNS_PROVIDERS[$PICK]}"
        info "Applying $pn ..."
    elif (( PICK == ${#DNS_PROVIDERS[@]} )); then
        read -rp "Enter DNS server IPs (space/comma separated, IPv4 and/or IPv6): " raw
        local ip
        for ip in ${raw//,/ }; do
            if ! valid_ip "$ip"; then err "Invalid IP: $ip"; return; fi
            if [[ $ip == *:* ]]; then v6+="${v6:+,}$ip"; else v4+="${v4:+,}$ip"; fi
        done
        [[ -z "$v4$v6" ]] && { warn "Nothing entered."; return; }
    else
        info "Resetting to automatic DNS..."
    fi

    apply_dns "$con" "$v4" "$v6" && { sleep 1; echo; show_current_dns; }
}

dns_benchmark() {
    have dig || { err "dig not found (install dnsutils / bind-utils)."; return; }
    info "Benchmarking providers (resolving a few domains each)..."
    local domains=(example.com wikipedia.org github.com archlinux.org)
    printf "\n  %-32s %s\n" "Provider" "Avg response (ms)"
    local p pn pv4 ip d t total count avg
    for p in "${DNS_PROVIDERS[@]}"; do
        IFS='|' read -r pn pv4 _ <<<"$p"
        ip=${pv4%%,*}; total=0; count=0
        for d in "${domains[@]}"; do
            t=$(dig +tries=1 +time=2 "@$ip" "$d" 2>/dev/null | awk '/Query time/{print $4}')
            [[ -n "$t" ]] && { total=$((total + t)); count=$((count + 1)); }
        done
        if (( count )); then avg=$((total / count)); else avg="timeout"; fi
        printf "  %-32s %s\n" "$pn" "$avg"
    done
}

menu_dns() {
    while true; do
        clear
        echo "${W}=== DNS Settings ===${N}"
        echo "  1) Change DNS (public providers / custom / reset)"
        echo "  2) Show current DNS"
        echo "  3) Benchmark public DNS providers"
        echo "  0) Back"
        read -rp "> " c
        case $c in
            1) dns_change; pause ;;
            2) show_current_dns; pause ;;
            3) dns_benchmark; pause ;;
            0) return ;;
        esac
    done
}

###############################################################################
# 3) NETWORK TOOLS
###############################################################################
t_interfaces() {
    echo "${W}Interfaces:${N}"; ip -br addr
    echo; echo "${W}Default route / gateway:${N}"; ip route show default
    echo; echo "${W}Link details:${N}"; ip -br link
}

t_ping() {
    read -rp "Host to ping [1.1.1.1]: " h; h=${h:-1.1.1.1}
    read -rp "Count [4]: " n; n=${n:-4}
    ping -c "$n" "$h"
}

t_trace() {
    read -rp "Host to trace [1.1.1.1]: " h; h=${h:-1.1.1.1}
    if   have mtr;        then mtr -rwz -c 10 "$h"
    elif have traceroute; then traceroute "$h"
    elif have tracepath;  then tracepath "$h"
    else err "Install mtr, traceroute or tracepath."; fi
}

t_lookup() {
    read -rp "Domain to look up: " d; [[ -z "$d" ]] && return
    read -rp "Record type [A]: " r; r=${r:-A}
    read -rp "DNS server to use (blank = system): " s
    if have dig; then
        dig ${s:+@"$s"} "$d" "$r" +noall +answer +stats
    elif have host; then
        host -t "$r" "$d" ${s:+"$s"}
    elif have nslookup; then
        nslookup -type="$r" "$d" ${s:+"$s"}
    else err "Install dig/host/nslookup."; fi
}

t_publicip() {
    have curl || { err "curl not found."; return; }
    local ip
    ip=$(curl -s --max-time 6 https://api.ipify.org || curl -s --max-time 6 https://ifconfig.me)
    [[ -n "$ip" ]] && { ok "Public IP: $ip"; have whois && whois "$ip" 2>/dev/null | grep -iE '^(netname|orgname|org-name|country|descr):' | head -5; } \
                   || err "Could not determine public IP (offline?)."
}

t_diagnose() {
    echo "${W}Connectivity check${N}"
    local gw; gw=$(ip route show default | awk '/default/{print $3; exit}')
    if [[ -n "$gw" ]]; then
        ping -c1 -W2 "$gw" >/dev/null 2>&1 && ok "Gateway $gw reachable" || err "Gateway $gw unreachable"
    else err "No default gateway"; fi
    ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 && ok "Internet (1.1.1.1) reachable" || err "Internet (1.1.1.1) unreachable"
    if getent hosts example.com >/dev/null 2>&1; then ok "DNS resolution works"; else err "DNS resolution failed"; fi
    if have curl; then
        curl -s --max-time 6 -o /dev/null -w "%{http_code}" https://example.com | grep -q '^[23]' \
            && ok "HTTPS works" || err "HTTPS failed"
    fi
}

t_ports() {
    echo "${W}Listening sockets:${N}"
    $SUDO ss -tulpn
}

t_portcheck() {
    read -rp "Host: " h; read -rp "Port: " p
    [[ -z "$h" || -z "$p" ]] && return
    if have nc; then nc -zv -w 4 "$h" "$p"
    else (timeout 4 bash -c "exec 3<>/dev/tcp/$h/$p" && ok "$h:$p open") 2>/dev/null || err "$h:$p closed/unreachable"; fi
}

t_whois() {
    have whois || { err "whois not installed."; return; }
    read -rp "Domain or IP: " d; [[ -n "$d" ]] && whois "$d" | head -60
}

t_flushdns() {
    local done=0
    if have resolvectl; then $SUDO resolvectl flush-caches && ok "systemd-resolved cache flushed" && done=1; fi
    if systemctl is-active --quiet nscd 2>/dev/null; then $SUDO nscd -i hosts && ok "nscd flushed" && done=1; fi
    if systemctl is-active --quiet dnsmasq 2>/dev/null; then $SUDO systemctl restart dnsmasq && ok "dnsmasq restarted" && done=1; fi
    (( done )) || warn "No known DNS cache service is running."
}

t_speed() {
    have curl || { err "curl not found."; return; }
    info "Downloading 25 MB test file from Cloudflare..."
    curl -s --max-time 60 -o /dev/null -w "Speed: %{speed_download} bytes/s  (%{time_total}s)\n" \
        "https://speed.cloudflare.com/__down?bytes=25000000" \
        | awk '{ if ($2+0>0) printf "Speed: %.2f Mbit/s  %s\n", $2*8/1000000, $3; else print }'
}

t_neighbors() { echo "${W}ARP / neighbor table:${N}"; ip neigh show; }

t_restart_nm() {
    $SUDO systemctl restart NetworkManager && ok "NetworkManager restarted" || err "Restart failed."
}

t_ipinfo_scan() {
    have nmap || { err "nmap not installed."; return; }
    local net; net=$(ip -o -f inet addr show scope global | awk '{print $4; exit}')
    read -rp "Network to scan [$net]: " n; n=${n:-$net}
    [[ -z "$n" ]] && return
    $SUDO nmap -sn "$n"
}

menu_tools() {
    while true; do
        clear
        echo "${W}=== Network Tools ===${N}"
        cat <<EOF
   1) Interfaces, IPs and gateway
   2) Ping a host
   3) Traceroute / mtr
   4) DNS lookup (dig/host/nslookup)
   5) Show public IP
   6) Quick connectivity diagnosis
   7) Listening ports (ss)
   8) Check if a remote port is open
   9) Whois
  10) Flush DNS cache
  11) Download speed test
  12) ARP / neighbor table
  13) Scan local network for hosts (nmap)
  14) Restart NetworkManager
   0) Back
EOF
        read -rp "> " c
        echo
        case $c in
            1) t_interfaces ;;   2) t_ping ;;       3) t_trace ;;
            4) t_lookup ;;       5) t_publicip ;;    6) t_diagnose ;;
            7) t_ports ;;        8) t_portcheck ;;   9) t_whois ;;
            10) t_flushdns ;;    11) t_speed ;;      12) t_neighbors ;;
            13) t_ipinfo_scan ;; 14) t_restart_nm ;;
            0) return ;;
            *) warn "Invalid choice." ;;
        esac
        pause
    done
}

###############################################################################
# MAIN
###############################################################################
main_menu() {
    while true; do
        clear
        echo "${B}${W}╔══════════════════════════════════╗"
        echo "║   Network & DNS Manager          ║"
        echo "╚══════════════════════════════════╝${N}"
        echo "  1) Networks  - scan & connect"
        echo "  2) DNS       - change / reset / benchmark"
        echo "  3) Tools     - ping, traceroute, lookup, ..."
        echo "  0) Exit"
        read -rp "> " c
        case $c in
            1) menu_wifi ;;
            2) menu_dns ;;
            3) menu_tools ;;
            0|q|Q) echo "Bye."; exit 0 ;;
        esac
    done
}

# Run as one compound command so it is fully parsed before stdin is swapped.
# This lets the menu work when piped from curl (curl ... | bash).
{
    if [[ ! -t 0 ]]; then
        if [[ -r /dev/tty ]]; then exec </dev/tty; else err "No terminal available for interactive input."; exit 1; fi
    fi
    main_menu
}
