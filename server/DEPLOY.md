# Putting the society server online

Two ways, both free and both running the same server:

- **A Raspberry Pi (or any always-on Linux box) at home**, shared through
  Tailscale Funnel. No router changes, and it works with any home internet.
  The address looks like `https://yourpi.tail1234.ts.net`.
- **An Oracle Cloud machine** with a free DuckDNS name (see further down).

## Raspberry Pi at home (Tailscale Funnel)

Needs a Pi 3/4/5 running **64-bit** Raspberry Pi OS (Bookworm or newer), on
your network and reachable by SSH. It can share the Pi with other things,
such as a C64 hub: the golf server only uses a little memory, and the
installer won't take ports that are already in use.

1. **A free Tailscale account:** sign up at <https://tailscale.com> (Google,
   GitHub or Microsoft login). Your friends don't need one.
2. **Install:** SSH to the Pi and run:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/mikehellyer/simple-golf/main/server/deploy/install.sh | sudo bash -s -- --funnel
   ```

   - The first time, it shows a Tailscale sign-in link: open it and approve
     the Pi.
   - If Tailscale says Funnel or HTTPS isn't enabled for your account, it
     shows another link: open it, approve, and the install carries on.
   - If something on the Pi already uses port 8000, add `--port 8090` (any
     free port). If another app already uses Tailscale Funnel on port 443,
     the installer picks port 8443 for golf automatically.
3. **Check:** the installer finishes by printing the address. Open
   `https://THAT-ADDRESS/api/v1/health` in a browser on your phone with Wi-Fi
   off; you should see `{"ok":true,...}`.
4. **Play:** in Simple-Golf, go to clubhouse → **Online society**, enter the
   address as the server, then **Create account** and create your society.
   Share its invite code with friends.

**Look after the SD card:** the database is small, but SD cards do wear
out. Copy backups somewhere else now and then (see below), or run the Pi
from a USB SSD.

## Oracle Cloud machine

This takes about 30–45 minutes the first time.

### 1. Oracle Cloud account

1. Sign up at <https://signup.cloud.oracle.com>. Oracle asks for a credit
   card to verify you; Always Free resources aren't charged.
2. Choose your **home region** carefully (e.g. *UK South (London)*). It can't
   be changed, and free resources only live there.
3. **Recommended:** upgrade the account to **Pay As You Go** (Billing →
   Upgrade). You still pay nothing while you stay within the Always Free
   limits, and it's widely reported to stop Oracle reclaiming "idle" free
   machines. A server for a few friends often looks idle: under 20% CPU,
   network and memory use for 7 days. Then set a budget alert (Billing →
   Budgets) for £1 so you'd hear about any charge.

### 2. Create the machine

Compute → Instances → **Create instance**:

- **Image:** Canonical Ubuntu 24.04.
- **Shape:** Ampere → `VM.Standard.A1.Flex`, 1 OCPU, 6 GB memory. That's
  plenty, and it's within the free 2 OCPU / 12 GB. If Oracle says "out of
  capacity", try another availability domain, or pick
  `VM.Standard.E2.1.Micro` (AMD, 1 GB, also free); the server runs fine on it.
- **Networking:** keep the defaults (new network, public IPv4 address).
- **SSH keys:** upload your public key. On this computer:
  `cat ~/.ssh/id_ed25519.pub` (make one with `ssh-keygen -t ed25519` if
  that file doesn't exist).

When it's running, note its **public IP address**.

### 3. Open the web ports

Instance page → the subnet → **Security list** → **Add ingress rules**: two
rules with source `0.0.0.0/0`, protocol TCP, destination ports `80` and
`443`. (The install script opens the same ports in the machine's own
firewall.)

### 4. A free web address

1. Go to <https://www.duckdns.org> and sign in (GitHub works).
2. Add a sub-domain, e.g. `fridayfour`, and set its IP to the machine's
   public IP.

### 5. Install the server

```bash
ssh ubuntu@THE.PUBLIC.IP
curl -fsSL https://raw.githubusercontent.com/mikehellyer/simple-golf/main/server/deploy/install.sh | sudo bash -s -- --domain fridayfour.duckdns.org
```

It installs Python, the web server (Caddy, which gets and renews the HTTPS
certificate automatically) and the society service, then sets up a nightly
database backup. When it finishes, open
`https://fridayfour.duckdns.org/api/v1/health` in a browser. You should see
`{"ok":true,...}`.

### 6. Play

In Simple-Golf: clubhouse → **Online society** → enter
`fridayfour.duckdns.org` as the server → **Create account** → create your
society. Share its invite code with friends.

## Looking after it

- **Update the server** to the latest code: run the same install command again, with the same options.
- **Logs:** `sudo journalctl -u simplegolf -f`
- **Funnel status (Pi):** `tailscale funnel status`
- **Backups:** `/var/lib/simplegolf/backups/` (14 days kept). To copy one
  home: `scp USER@MACHINE:/var/lib/simplegolf/backups/simplegolf-DATE.db .`
- **Restore:** `sudo systemctl stop simplegolf`, copy the backup over
  `/var/lib/simplegolf/simplegolf.db`, then `sudo systemctl start simplegolf`.
