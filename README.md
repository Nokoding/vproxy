# vproxy

A personal fork of [0x676e67/vproxy](https://github.com/0x676e67/vproxy), a
high-performance `HTTP`/`HTTPS`/`SOCKS5` proxy server, wired up below to run
as a self-healing personal proxy inside a free GitHub Codespace. License:
[GPL-3.0](./LICENSE).

## This fork: a self-restarting personal proxy in a free Codespace

This fork of vproxy is wired up as a small, self-healing personal HTTP proxy that
runs entirely inside a free [GitHub Codespace](https://github.com/features/codespaces)
and is reachable from anywhere (an iPad, a phone, another laptop) with no server to
rent and no domain to buy. Everything below lives in `.devcontainer/` and starts
automatically every time the Codespace boots.

### Why it's built this way

vproxy needs to accept `CONNECT` requests and raw TCP from whatever device is using
it as a proxy. GitHub Codespaces port forwarding can't do that — it's an
HTTPS-terminating reverse proxy layer (`*.app.github.dev`), not a raw TCP
passthrough, so a device dialing a forwarded Codespace port directly gets rejected
or mangled traffic. (The same limitation is why a `cloudflared` quick tunnel doesn't
work here either — it's also HTTP(S)-only at Cloudflare's edge.)

The fix is [bore](https://github.com/ekzhang/bore): a plain TCP tunnel. The
Codespace only ever makes an *outbound* connection to the free public relay at
`bore.pub`, which does have a real public IP — so `bore.pub` becomes the actual
address a device connects to, and it forwards raw bytes straight through to vproxy
running inside the Codespace. No inbound connection to the Codespace itself is ever
needed.

```
 iPad / phone  --->  bore.pub:54584  --->  (outbound-only tunnel)  --->  bore client  --->  vproxy:8080
 (proxy client)      (free public relay)                                (in Codespace)     (in Codespace)
```

### What's actually running

| Process | File | Job |
|---|---|---|
| `vproxy` (plain) | — | the HTTP proxy, bound to `0.0.0.0:8080` |
| `vproxy` (TLS) | — | a second instance in `https` mode, bound to `0.0.0.0:8443`, presenting a real cert for `<DUCKDNS_DOMAIN>.duckdns.org` |
| `bore` ×2 | — | tunnels port 8080 out to `bore.pub:54584` (plain) and port 8443 to `bore.pub:54585` (TLS) |
| `acme.sh` | `.devcontainer/tls-cert.sh` | issues/renews the Let's Encrypt cert for the TLS proxy via a DuckDNS DNS-01 challenge (no inbound port needed); cached and only reissued when close to expiry |
| watchdog | `.devcontainer/restart-proxy.sh` | health-checks the proxy every 30s; kills and respawns vproxy/bore on crash *or* hang |
| `ollama serve` + `llama3.2:3b` | `.devcontainer/ai-triage.sh` | a small model running **locally in the Codespace** (no external API, no cost) that reads the recent logs on every failure and decides whether it's worth emailing about, plus writes a plain-English guess at the cause |
| email alerts | `.devcontainer/alert-email.sh` | sends the AI's verdict via the [MailerSend](https://www.mailersend.com/) API |

The TLS variant exists so the proxy can pass as ordinary HTTPS traffic (a
normal TLS handshake to a real hostname) on networks that block or inspect
plain HTTP proxying — the plain HTTP one keeps running regardless, and if
cert issuance ever fails, only the TLS variant is skipped.

All of the above are launched by one command, `restart-proxy` (symlinked to
`/usr/local/bin/restart-proxy`), which itself runs automatically on every Codespace
start via `postStartCommand`. Each process is wrapped in its own respawn loop, so a
crash brings it straight back; the watchdog additionally catches the case where
vproxy is still running but has silently wedged (no crash, so a respawn loop alone
wouldn't notice). Port `8080` is also flipped to public visibility automatically on
every run, so nothing here needs a manual fix after a Codespace restart.

If the local model is ever unavailable (still loading, Ollama down, bad output),
alerting doesn't silently stop — `ai-triage.sh` fails closed and the watchdog falls
back to a fixed rule (always alert on the first failure in a bad stretch, then throttle
to once per 15 minutes unless it's clearly getting worse). Recovery itself (the
kill-and-respawn) always happens immediately and unconditionally — it never waits on
the model.

### Using the proxy

Plain HTTP proxy — works everywhere, but is recognizable as proxy traffic to
anything inspecting the connection:

```
Server: bore.pub
Port:   54584
```

TLS ("HTTPS" / "secure") proxy — same proxy, but the connection itself looks
like an ordinary HTTPS request to a real hostname, for networks that block or
inspect plain HTTP proxying:

```
Server: cdspc.duckdns.org
Port:   54585
```

Use whichever your device/app's proxy settings support (look for a "secure
proxy" or "HTTPS proxy" toggle to select the TLS one). No auth configured on
either. Because both are tunneled through a free, shared public relay, expect
slowdowns (not failures) under heavy parallel load, e.g. a media-heavy page
loading many resources at once.

### Operating it

```bash
# from a terminal inside the Codespace
restart-proxy
```

Kills and relaunches everything (vproxy, bore, the watchdog, Ollama), re-publishes
port 8080, and prints the proxy address. Useful after editing any of the
`.devcontainer/*.sh` scripts, or if something needs a manual kick.

Logs, if you need them:

```bash
tail -f /tmp/vproxy.log            # plain HTTP vproxy output
tail -f /tmp/vproxy-tls.log        # TLS vproxy output
tail -f /tmp/bore.log              # bore tunnel (plain) connection log
tail -f /tmp/bore-tls.log          # bore tunnel (TLS) connection log
tail -f /tmp/acme.log              # Let's Encrypt cert issuance/renewal
tail -f /tmp/proxy-watchdog.log    # health-check failures/restarts, alert decisions
tail -f /tmp/ollama.log            # local model server log
```

### One-time setup this repo needs

Email alerts and the TLS proxy need four [Codespaces secrets](https://github.com/settings/codespaces)
(Settings → Codespaces secrets → New secret, scoped to this repo) — never commit
these to the repo itself:

- `MAILERSEND_API_TOKEN` — a MailerSend API token scoped to **Email: send** only
  (no need for full account access)
- `MAILERSEND_FROM` — the sender address MailerSend gave you (e.g.
  `alerts@yoursubdomain.mlsender.net` for a trial domain)
- `DUCKDNS_TOKEN` — your [DuckDNS](https://www.duckdns.org/) account token; used
  both to keep the domain pointed at bore.pub's current IP and to complete the
  DNS-01 challenge for the TLS proxy's Let's Encrypt certificate
- `DUCKDNS_DOMAIN` — the bare subdomain you registered on DuckDNS (e.g. `cdspc`
  for `cdspc.duckdns.org`), no `.duckdns.org` suffix

Codespaces secrets are only injected into the environment when the Codespace
*starts* — after adding or changing one, stop and restart the Codespace (Command
Palette → "Codespaces: Stop Current Codespace", then reopen it) rather than just
opening a new terminal.

Everything else (vproxy, bore, Ollama + the model) installs itself automatically the
first time the Codespace is created, via `onCreateCommand` in
`.devcontainer/devcontainer.json`.

## Upstream vproxy reference

<details>

<summary>CLI manual, install methods, protocol config, and benchmarks for the
underlying vproxy binary itself (not specific to this fork's Codespace
setup) — expand if you need to run vproxy manually or tune it directly</summary>

### Features

- Proxy extensions
- Concurrency limits 
- Basic authentication
- Auto protocol detection
- Kernel-space zero-copy
- `IPv4`/`IPv6` dual-stack
- Service binding to specific `CIDR` addresses
- SOCKS5: `CONNECT`/`BIND`/`ASSOCIATE`  

### Manual

```shell
$ vproxy -h
A high-performance HTTP/HTTPS/SOCKS5 proxy server

Usage: vproxy
       vproxy <COMMAND>

Commands:
  run      Run server
  start    Start server daemon
  restart  Restart server daemon
  stop     Stop server daemon
  ps       Show server daemon process
  log      Show server daemon log
  self     Modify server installation
  help     Print this message or the help of the given subcommand(s)

Options:
  -h, --help     Print help
  -V, --version  Print version
```

### Installation

<details>

<summary>If you need more detailed installation and usage information, please check here</summary>

#### Install

- curl

```bash
curl -sSL https://raw.githubusercontent.com/0x676e67/vproxy/main/.github/install.sh | bash
```

- wget

```bash
wget -qO- https://raw.githubusercontent.com/0x676e67/vproxy/main/.github/install.sh | bash
```

- cargo

```bash
cargo install vproxy
```

- Dokcer

```bash
docker run --rm -it ghcr.io/0x676e67/vproxy:latest run http
```

#### Note

If you run the program as root, it will automatically configure the sysctl `net.ipv6.ip_nonlocal_bind=1`, `net.ipv6.conf.all.disable_ipv6`, and `ip route add local 2001:470:e953::/48 dev lo` for you. Otherwise you will need to configure these settings manually.

If no subnet is configured, the local default network proxy request will be used. When the local machine sets the priority `Ipv4`/`Ipv6` and the priority is `Ipv4`, it will always use `Ipv4` to make requests (if any).

```shell
# Enable binding to non-local IPv6 addresses
sudo sysctl net.ipv6.ip_nonlocal_bind=1

# Enable IPv6
sudo sysctl net.ipv6.conf.all.disable_ipv6=0

# Replace with your IPv6 subnet
sudo ip route add local 2001:470:e953::/48 dev lo

# Run the server http/socks5
vproxy run -i 2001:470:e953::/48 http

# Start the daemon (runs in the background), requires sudo
sudo vproxy start -i 2001:470:e953::/48 http

# Restart the daemon, requires sudo
sudo vproxy restart

# Stop the daemon, requires sudo
sudo vproxy stop

# Show daemon log
vproxy log

# Show daemon status
vproxy status

# Download and install updates to vproxy
vproxy self update

# Uninstall vproxy
vproxy self uninstall

# Test loop request
while true; do curl -x http://127.0.0.1:8100 -s https://api.ip.sb/ip -A Mozilla; done
...
2001:470:e953:5b75:c862:3328:3e8f:f4d1
2001:470:e953:b84d:ad7d:7399:ade5:4c1c
2001:470:e953:4f88:d5ca:84:83fd:6faa
2001:470:e953:29f3:41e2:d3f2:4a49:1f22
2001:470:e953:98f6:cb40:9dfd:c7ab:18c4
2001:470:e953:f1d7:eb68:cc59:b2d0:2c6f

```

#### Multi-Protocol Support

vproxy supports multiple types of proxy servers with flexible configuration options. HTTP, HTTPS, and SOCKS5 proxies can run independently, or use the auto-detection mode to handle all protocols on a single port. Each server type supports authentication, custom binding addresses, and advanced socket configurations.

1. HTTP Proxy

```bash
# Basic HTTP proxy
vproxy run http

# HTTP proxy with authentication
vproxy run http -u username -p password

# HTTP proxy on custom port
vproxy run --bind 0.0.0.0:8080 http
```

2. HTTPS Proxy

```bash
# HTTPS proxy with TLS certificates
vproxy run https --tls-cert cert.pem --tls-key key.pem

# HTTPS proxy with authentication
vproxy run https --tls-cert cert.pem --tls-key key.pem -u username -p password
```

If no TLS certificate is provided, vproxy will automatically generate a self-signed certificate for HTTPS connections.

3. SOCKS5 Proxy

```bash
# Basic SOCKS5 proxy
vproxy run socks5

# SOCKS5 proxy with authentication
vproxy run socks5 -u username -p password

# SOCKS5 proxy on custom port
vproxy run --bind 0.0.0.0:1080 socks5
```

4. Auto Protocol Detection

```bash
# Auto-detect HTTP/HTTPS/SOCKS5 protocols on single port
vproxy run auto

# Auto-detect with HTTPS support
vproxy run auto --tls-cert cert.pem --tls-key key.pem

# Auto-detect with authentication
vproxy run auto -u username -p password --tls-cert cert.pem --tls-key key.pem
```

The auto-detection server automatically identifies the protocol type and routes connections to the appropriate handler.


- TTL Extension

Append `-ttl-` to the username, where TTL is a fixed value (e.g., `username-ttl-2`). The TTL value is the number of requests that can be made with the same IP. When the TTL value is reached, the IP will be changed.

- Session Extension

Append `-session-id` to the username, where session is a fixed value and ID is an arbitrary random value (e.g., `username-session-123456`). Keep the Session ID unchanged to use a fixed IP.

- Range Extension

Append `-range-id` to the username, where range is a fixed value and ID is any random value (e.g. `username-range-123456`). By keeping the Range ID unchanged, you can use a fixed CIDR range in a fixed range. in addition, you must set the startup parameter `--cidr-range`, and the length is within a valid range.

#### Examples

- Http proxy session with username and password:

```shell
vproxy run --bind 127.0.0.1:1080 -i 2001:470:70c6::/48 http -u test -p test

$ for i in `seq 1 10`; do curl -x "http://test-session-123456789:test@127.0.0.1:1080" https://api6.ipify.org; done
2001:470:70c6:93ee:9b7c:b4f9:4913:22f5
2001:470:70c6:93ee:9b7c:b4f9:4913:22f5
2001:470:70c6:93ee:9b7c:b4f9:4913:22f5

$ for i in `seq 1 10`; do curl -x "http://test-session-987654321:test@127.0.0.1:1080" https://api6.ipify.org; done
2001:470:70c6:41d0:14fd:d025:835a:d102
2001:470:70c6:41d0:14fd:d025:835a:d102
2001:470:70c6:41d0:14fd:d025:835a:d102
```

- Socks5 proxy session with username and password

```shell
vproxy run --bind 127.0.0.1:1080 -i 2001:470:70c6::/48 socks5 -u test -p test

$ for i in `seq 1 3`; do curl -x "socks5h://test-session-123456789:test@127.0.0.1:1080" https://api6.ipify.org; done
2001:470:70c6:93ee:9b7c:b4f9:4913:22f5
2001:470:70c6:93ee:9b7c:b4f9:4913:22f5
2001:470:70c6:93ee:9b7c:b4f9:4913:22f5

$ for i in `seq 1 3`; do curl -x "socks5h://test-session-987654321:test@127.0.0.1:1080" https://api6.ipify.org; done
2001:470:70c6:41d0:14fd:d025:835a:d102
2001:470:70c6:41d0:14fd:d025:835a:d102
2001:470:70c6:41d0:14fd:d025:835a:d102

```

- TTL proxy session with username and password

```shell
vproxy run --bind 127.0.0.1:1080 -i 2001:470:70c6::/48 socks5 -u test -p test

$ for i in `seq 1 3`; do curl -x "socks5h://test-ttl-2:test@127.0.0.1:1080" https://api6.ipify.org; done
2001:470:70c6:93ee:9b7c:b4f9:4913:22f5
2001:470:70c6:93ee:9b7c:b4f9:4913:22f5
2001:470:70c6:93ee:9b7c:b4f9:4913:22f6

$ for i in `seq 1 3`; do curl -x "socks5h://test-ttl-2:test@127.0.0.1:1080" https://api6.ipify.org; done
2001:470:70c6:41d0:14fd:d025:835a:d102
2001:470:70c6:41d0:14fd:d025:835a:d102
2001:470:70c6:41d0:14fd:d025:835a:d105
```

</details>

### Benchmark

<details>

<summary>If you need more detailed benchmark information, please check here</summary>

#### Hardware/Software

- CPU: Apple M3 Max (16) @ 4.06 GHz
- OS: Ubuntu 25.04 aarch64 (6.15.11-orbstack-00542-g4f455d264886)
- Iperf3: 3.18
- Proxychains-ng: 4.17

> Tests performed in virtualized environment (OrbStack). Performance may vary due to VM overhead and resource sharing.

#### Topology

```bash
iperf3 server <---> socks5 server <---> iperf3 client
```

#### vproxy

1. version `vproxy 2.5.1`
2. repository: `https://github.com/0x676e67/vproxy`
3. command

```bash
vproxy run socks5
```

- Upload

```bash
$ proxychains iperf3 -c 127.0.0.1
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.01  sec   167 GBytes   143 Gbits/sec    1            sender
[  5]   0.00-10.01  sec   167 GBytes   143 Gbits/sec                  receiver
```

```bash
$ proxychains iperf3 -c 127.0.0.1 -P 10
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  9]   0.00-10.00  sec  40.8 GBytes  35.1 Gbits/sec    9            sender
[  9]   0.00-10.00  sec  40.8 GBytes  35.1 Gbits/sec                  receiver
[ 11]   0.00-10.00  sec  43.6 GBytes  37.4 Gbits/sec   10            sender
[ 11]   0.00-10.00  sec  43.6 GBytes  37.4 Gbits/sec                  receiver
[ 13]   0.00-10.00  sec  41.9 GBytes  36.0 Gbits/sec   11            sender
[ 13]   0.00-10.00  sec  41.9 GBytes  36.0 Gbits/sec                  receiver
[ 15]   0.00-10.00  sec  42.2 GBytes  36.2 Gbits/sec   10            sender
[ 15]   0.00-10.00  sec  42.2 GBytes  36.2 Gbits/sec                  receiver
[ 17]   0.00-10.00  sec  41.2 GBytes  35.4 Gbits/sec   11            sender
[ 17]   0.00-10.00  sec  41.2 GBytes  35.4 Gbits/sec                  receiver
[ 19]   0.00-10.00  sec  41.2 GBytes  35.4 Gbits/sec   10            sender
[ 19]   0.00-10.00  sec  41.2 GBytes  35.4 Gbits/sec                  receiver
[ 21]   0.00-10.00  sec  43.3 GBytes  37.2 Gbits/sec   15            sender
[ 21]   0.00-10.00  sec  43.3 GBytes  37.2 Gbits/sec                  receiver
[ 23]   0.00-10.00  sec  40.6 GBytes  34.8 Gbits/sec    8            sender
[ 23]   0.00-10.00  sec  40.6 GBytes  34.8 Gbits/sec                  receiver
[ 25]   0.00-10.00  sec  40.2 GBytes  34.5 Gbits/sec   12            sender
[ 25]   0.00-10.00  sec  40.2 GBytes  34.5 Gbits/sec                  receiver
[ 27]   0.00-10.00  sec  42.6 GBytes  36.6 Gbits/sec   10            sender
[ 27]   0.00-10.00  sec  42.6 GBytes  36.6 Gbits/sec                  receiver
[SUM]   0.00-10.00  sec   418 GBytes   359 Gbits/sec  106             sender
[SUM]   0.00-10.00  sec   417 GBytes   359 Gbits/sec                  receiver
```

- Download

```bash
$ proxychains iperf3 -c 127.0.0.1 -R
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  9]   0.00-10.01  sec   116 GBytes  99.5 Gbits/sec    0            sender
[  9]   0.00-10.01  sec   116 GBytes  99.5 Gbits/sec                  receiver
```

```bash
$ proxychains iperf3 -c 127.0.0.1 -R -P 10
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  9]   0.00-10.00  sec  42.7 GBytes  36.7 Gbits/sec   10            sender
[  9]   0.00-10.00  sec  42.7 GBytes  36.7 Gbits/sec                  receiver
[ 11]   0.00-10.00  sec  45.8 GBytes  39.4 Gbits/sec   12            sender
[ 11]   0.00-10.00  sec  45.8 GBytes  39.4 Gbits/sec                  receiver
[ 13]   0.00-10.00  sec  43.5 GBytes  37.3 Gbits/sec    9            sender
[ 13]   0.00-10.00  sec  43.5 GBytes  37.3 Gbits/sec                  receiver
[ 15]   0.00-10.00  sec  42.4 GBytes  36.4 Gbits/sec    7            sender
[ 15]   0.00-10.00  sec  42.4 GBytes  36.4 Gbits/sec                  receiver
[ 17]   0.00-10.00  sec  42.1 GBytes  36.1 Gbits/sec   13            sender
[ 17]   0.00-10.00  sec  42.1 GBytes  36.1 Gbits/sec                  receiver
[ 19]   0.00-10.00  sec  40.1 GBytes  34.4 Gbits/sec    6            sender
[ 19]   0.00-10.00  sec  40.1 GBytes  34.4 Gbits/sec                  receiver
[ 21]   0.00-10.00  sec  42.3 GBytes  36.3 Gbits/sec    8            sender
[ 21]   0.00-10.00  sec  42.3 GBytes  36.3 Gbits/sec                  receiver
[ 23]   0.00-10.00  sec  43.1 GBytes  37.0 Gbits/sec    9            sender
[ 23]   0.00-10.00  sec  43.1 GBytes  37.0 Gbits/sec                  receiver
[ 25]   0.00-10.00  sec  42.8 GBytes  36.8 Gbits/sec    8            sender
[ 25]   0.00-10.00  sec  42.8 GBytes  36.7 Gbits/sec                  receiver
[ 27]   0.00-10.00  sec  42.4 GBytes  36.4 Gbits/sec    8            sender
[ 27]   0.00-10.00  sec  42.4 GBytes  36.4 Gbits/sec                  receiver
[SUM]   0.00-10.00  sec   427 GBytes   367 Gbits/sec   90             sender
[SUM]   0.00-10.00  sec   427 GBytes   367 Gbits/sec                  receiver
```

#### hev-socks5-server

1. version `hev-socks5-server 2.7.0`
2. repository: `https://github.com/heiher/hev-socks5-server`
3. Command

```bash
# workers: 16
hev-socks5-server conf/main.yml
```

- Upload

```bash
$ proxychains iperf3 -c 127.0.0.1
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.01  sec   167 GBytes   143 Gbits/sec    1            sender
[  5]   0.00-10.05  sec   167 GBytes   143 Gbits/sec                  receiver
```

```bash
$ proxychains iperf3 -c 127.0.0.1 -P 10
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  9]   0.00-10.01  sec  57.2 GBytes  49.1 Gbits/sec    0            sender
[  9]   0.00-10.04  sec  57.2 GBytes  49.0 Gbits/sec                  receiver
[ 11]   0.00-10.01  sec  55.9 GBytes  48.0 Gbits/sec    0            sender
[ 11]   0.00-10.04  sec  55.9 GBytes  47.8 Gbits/sec                  receiver
[ 13]   0.00-10.01  sec  30.6 GBytes  26.2 Gbits/sec    1            sender
[ 13]   0.00-10.04  sec  30.6 GBytes  26.1 Gbits/sec                  receiver
[ 15]   0.00-10.01  sec  31.4 GBytes  26.9 Gbits/sec    0            sender
[ 15]   0.00-10.04  sec  31.4 GBytes  26.8 Gbits/sec                  receiver
[ 17]   0.00-10.01  sec  57.0 GBytes  49.0 Gbits/sec    1            sender
[ 17]   0.00-10.04  sec  57.0 GBytes  48.8 Gbits/sec                  receiver
[ 19]   0.00-10.01  sec  56.7 GBytes  48.7 Gbits/sec    0            sender
[ 19]   0.00-10.04  sec  56.7 GBytes  48.5 Gbits/sec                  receiver
[ 21]   0.00-10.01  sec  31.2 GBytes  26.8 Gbits/sec    2            sender
[ 21]   0.00-10.04  sec  31.2 GBytes  26.7 Gbits/sec                  receiver
[ 23]   0.00-10.01  sec  30.7 GBytes  26.4 Gbits/sec    1            sender
[ 23]   0.00-10.04  sec  30.7 GBytes  26.3 Gbits/sec                  receiver
[ 25]   0.00-10.01  sec  58.4 GBytes  50.1 Gbits/sec    0            sender
[ 25]   0.00-10.04  sec  58.4 GBytes  49.9 Gbits/sec                  receiver
[ 27]   0.00-10.01  sec  59.5 GBytes  51.1 Gbits/sec    0            sender
[ 27]   0.00-10.04  sec  59.5 GBytes  50.9 Gbits/sec                  receiver
[SUM]   0.00-10.01  sec   469 GBytes   402 Gbits/sec    5             sender
[SUM]   0.00-10.04  sec   469 GBytes   401 Gbits/sec                  receiver
```

- Download

```bash
$ proxychains iperf3 -c 127.0.0.1 -R
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  9]   0.00-10.05  sec   116 GBytes  98.9 Gbits/sec    1            sender
[  9]   0.00-10.00  sec   116 GBytes  99.3 Gbits/sec                  receiver
```

```bash
$ proxychains iperf3 -c 127.0.0.1 -R -P 10
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  9]   0.00-10.03  sec  22.4 GBytes  19.2 Gbits/sec    1            sender
[  9]   0.00-10.00  sec  22.4 GBytes  19.2 Gbits/sec                  receiver
[ 11]   0.00-10.03  sec  64.9 GBytes  55.6 Gbits/sec    2            sender
[ 11]   0.00-10.00  sec  64.9 GBytes  55.7 Gbits/sec                  receiver
[ 13]   0.00-10.03  sec  59.2 GBytes  50.7 Gbits/sec    0            sender
[ 13]   0.00-10.00  sec  59.2 GBytes  50.8 Gbits/sec                  receiver
[ 15]   0.00-10.03  sec  37.2 GBytes  31.8 Gbits/sec    1            sender
[ 15]   0.00-10.00  sec  37.2 GBytes  31.9 Gbits/sec                  receiver
[ 17]   0.00-10.03  sec  37.1 GBytes  31.7 Gbits/sec    0            sender
[ 17]   0.00-10.00  sec  37.1 GBytes  31.8 Gbits/sec                  receiver
[ 19]   0.00-10.03  sec  64.3 GBytes  55.1 Gbits/sec    1            sender
[ 19]   0.00-10.00  sec  64.3 GBytes  55.2 Gbits/sec                  receiver
[ 21]   0.00-10.03  sec  22.3 GBytes  19.1 Gbits/sec    1            sender
[ 21]   0.00-10.00  sec  22.3 GBytes  19.1 Gbits/sec                  receiver
[ 23]   0.00-10.03  sec  21.6 GBytes  18.5 Gbits/sec    0            sender
[ 23]   0.00-10.00  sec  21.6 GBytes  18.5 Gbits/sec                  receiver
[ 25]   0.00-10.03  sec  59.6 GBytes  51.1 Gbits/sec    1            sender
[ 25]   0.00-10.00  sec  59.6 GBytes  51.2 Gbits/sec                  receiver
[ 27]   0.00-10.03  sec  62.1 GBytes  53.2 Gbits/sec    1            sender
[ 27]   0.00-10.00  sec  62.1 GBytes  53.3 Gbits/sec                  receiver
[SUM]   0.00-10.03  sec   451 GBytes   386 Gbits/sec    8             sender
[SUM]   0.00-10.00  sec   451 GBytes   387 Gbits/sec                  receiver
```

#### fast-socks5

1. version `fast-socks5 1.0.0-rc.0`
2. repository: `https://github.com/dizda/fast-socks5`
3. Command

```bash
cargo run -r --example server -- --listen-addr 127.0.0.1:1080 no-auth
```

- Upload

```bash
$ proxychains iperf3 -c 127.0.0.1
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  9]   0.00-10.01  sec  46.4 GBytes  39.8 Gbits/sec    0            sender
[  9]   0.00-10.05  sec  46.4 GBytes  39.7 Gbits/sec                  receiver
```

```bash
$ proxychains iperf3 -c 127.0.0.1 -P 10
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  9]   0.00-10.00  sec  26.8 GBytes  23.0 Gbits/sec    3            sender
[  9]   0.00-10.03  sec  26.8 GBytes  23.0 Gbits/sec                  receiver
[ 11]   0.00-10.00  sec  24.2 GBytes  20.8 Gbits/sec    7            sender
[ 11]   0.00-10.03  sec  24.2 GBytes  20.7 Gbits/sec                  receiver
[ 13]   0.00-10.00  sec  25.5 GBytes  21.9 Gbits/sec    3            sender
[ 13]   0.00-10.03  sec  25.5 GBytes  21.8 Gbits/sec                  receiver
[ 15]   0.00-10.00  sec  24.3 GBytes  20.9 Gbits/sec    9            sender
[ 15]   0.00-10.03  sec  24.3 GBytes  20.8 Gbits/sec                  receiver
[ 17]   0.00-10.00  sec  22.2 GBytes  19.1 Gbits/sec   15            sender
[ 17]   0.00-10.03  sec  22.2 GBytes  19.0 Gbits/sec                  receiver
[ 19]   0.00-10.00  sec  24.9 GBytes  21.4 Gbits/sec    7            sender
[ 19]   0.00-10.03  sec  24.9 GBytes  21.3 Gbits/sec                  receiver
[ 21]   0.00-10.00  sec  25.2 GBytes  21.7 Gbits/sec    6            sender
[ 21]   0.00-10.03  sec  25.2 GBytes  21.6 Gbits/sec                  receiver
[ 23]   0.00-10.00  sec  24.0 GBytes  20.6 Gbits/sec   12            sender
[ 23]   0.00-10.03  sec  24.0 GBytes  20.6 Gbits/sec                  receiver
[ 25]   0.00-10.00  sec  26.9 GBytes  23.1 Gbits/sec    0            sender
[ 25]   0.00-10.03  sec  26.9 GBytes  23.0 Gbits/sec                  receiver
[ 27]   0.00-10.00  sec  21.8 GBytes  18.7 Gbits/sec   13            sender
[ 27]   0.00-10.03  sec  21.8 GBytes  18.7 Gbits/sec                  receiver
[SUM]   0.00-10.00  sec   246 GBytes   211 Gbits/sec   75             sender
[SUM]   0.00-10.03  sec   246 GBytes   211 Gbits/sec                  receiver
```

- Download

```bash
$ proxychains iperf3 -c 127.0.0.1 -R
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  9]   0.00-10.05  sec  43.5 GBytes  37.2 Gbits/sec    0            sender
[  9]   0.00-10.01  sec  43.5 GBytes  37.4 Gbits/sec                  receiver
```

```bash
$ proxychains iperf3 -c 127.0.0.1 -R -P 10
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  9]   0.00-10.03  sec  20.1 GBytes  17.2 Gbits/sec   19            sender
[  9]   0.00-10.00  sec  20.1 GBytes  17.3 Gbits/sec                  receiver
[ 11]   0.00-10.03  sec  17.2 GBytes  14.8 Gbits/sec   19            sender
[ 11]   0.00-10.00  sec  17.2 GBytes  14.8 Gbits/sec                  receiver
[ 13]   0.00-10.03  sec  22.6 GBytes  19.4 Gbits/sec    7            sender
[ 13]   0.00-10.00  sec  22.6 GBytes  19.5 Gbits/sec                  receiver
[ 15]   0.00-10.03  sec  21.9 GBytes  18.7 Gbits/sec    1            sender
[ 15]   0.00-10.00  sec  21.9 GBytes  18.8 Gbits/sec                  receiver
[ 17]   0.00-10.03  sec  17.7 GBytes  15.1 Gbits/sec   14            sender
[ 17]   0.00-10.00  sec  17.7 GBytes  15.2 Gbits/sec                  receiver
[ 19]   0.00-10.03  sec  23.8 GBytes  20.4 Gbits/sec    2            sender
[ 19]   0.00-10.00  sec  23.8 GBytes  20.4 Gbits/sec                  receiver
[ 21]   0.00-10.03  sec  22.9 GBytes  19.6 Gbits/sec    1            sender
[ 21]   0.00-10.00  sec  22.9 GBytes  19.7 Gbits/sec                  receiver
[ 23]   0.00-10.03  sec  21.9 GBytes  18.7 Gbits/sec    7            sender
[ 23]   0.00-10.00  sec  21.9 GBytes  18.8 Gbits/sec                  receiver
[ 25]   0.00-10.03  sec  21.1 GBytes  18.0 Gbits/sec   10            sender
[ 25]   0.00-10.00  sec  21.1 GBytes  18.1 Gbits/sec                  receiver
[ 27]   0.00-10.03  sec  17.6 GBytes  15.1 Gbits/sec    6            sender
[ 27]   0.00-10.00  sec  17.6 GBytes  15.2 Gbits/sec                  receiver
[SUM]   0.00-10.03  sec   207 GBytes   177 Gbits/sec   86             sender
[SUM]   0.00-10.00  sec   207 GBytes   178 Gbits/sec                  receiver
```

</details>

</details>

## License

Original **vproxy** © [0x676e67](https://github.com/0x676e67), released under
the [GPL-3.0](./LICENSE) License. This fork's Codespace/proxy-cloaking setup
carries the same license.
