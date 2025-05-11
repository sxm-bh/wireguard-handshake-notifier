# WireGuard Handshake Notifier

A script designed to monitor WireGuard connections by measuring handshake timestamps within a predefined threshold, detecting changes in connection status, and sending notifications accordingly.</br></br>
Variation:</br>
`monitor_by_ip.sh`: Monitor peers identified by IP.</br>
`monitor_by_publickey`: Monitor peers identified by public key.

Sample message sent via Telegram API
![image](https://github.com/user-attachments/assets/bbed1710-99fd-4240-8f17-771eecc11890)

---

## Features

- Checks whether a peer has connected based on the latest handshake timestamp.
- Stores previous handshake info to detect status changes.
- Sends notifications (via Telegram, or customize to your preferred platform) only when a peer's status changes.
- Supports parsing for custom message with special characters.
- Configurable handshake timeout threshold.
- Lightweight and easy to integrate.

---

## Why Handshake Method

Using handshake timestamps to determine peer connectivity:

- **Active Connection Verification:** Handshake timestamps indicate actual data exchange and session activity, not just network reachability.
- **Firewall & NAT Friendly:** Unlike ping, which can be blocked, handshake data is part of the WireGuard protocol and less likely to be filtered.
- **Real-time Status:** Handshake updates reflect real connection status, providing accurate peer activity insights.
- **Less False Positives:** Pings can succeed even if the peer is not actively connected, whereas handshake timestamps show current active sessions.

---

## Setup Instructions

### 1. Save the Script

Choose between `monitor_by_ip.sh` or `monitor_by_publickey`. Feel free to rename the file to whatever you like.

```bash
git clone https://github.com/sxm-bh/wireguard-handshake-notifier.git
```

### 2. Make Script Executable

```bash
sudo chmod +x monitor_by_ip.sh
```

### 3. Schedule via Cron

Edit your crontab.

```bash
sudo crontab -e
```

To run this script every minute, add to your crontab:

```bash
* * * * * /path-to-your/monitor_by_ip.sh > /dev/null 2>&1
```
---

## Customization Tips

- Change `HANDSHAKE_THRESHOLD` to adjust how recent a handshake must be to consider the peer online.
- Replace the Telegram with your preferred notification method (e.g., email, Slack).
- Set your WireGuard interface name in `WG_INTERFACE`.
- Store your Telegram bot token and chat ID in the variables `BOT_TOKEN` and `CHAT_ID`.
- Store your WireGuard peers IP or PublicKey in the variable `PEER_IPS` or `PEER_PUBKEY`.
- For advanced parsing, modify the `sed` command in `esc_md2()`.

---

## Acknowledgement

This is my personal implementation of the script, based on [this project.](https://github.com/alfiosalanitri/wireguard-client-connection-notification)
