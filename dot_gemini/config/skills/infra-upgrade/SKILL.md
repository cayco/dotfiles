---
name: infra-upgrade
description: >-
  Execute or preflight software and firmware upgrades across the Rybaltow home
  infrastructure (Proxmox prox/prox2, Docker stacks on dokerz & LXCs, Home
  Assistant OS + Zigbee2MQTT, Synology NAS, UniFi network, DietPi SD audio Pis
  gora-pi & dol-pi, Valetudo vacuums, and smart-home appliances) following the
  Checkmk-gated Stage 0 -> Stage 8 runbook and AI changelog preflight.
---

# Rybałtów Infrastructure & Smart Home Upgrade Skill (`infra-upgrade`)

Whenever the user asks to check pending updates, run a monthly maintenance batch, or upgrade any server, container, hypervisor, network device, or smart-home appliance, **always follow this exact protocol** (documented in `/Users/krzysztofkajkowski/Downloads/Obsidian/Services/Software Upgrade & Maintenance Policy.md`).

## 1. Mandatory Pre-Upgrade AI Changelog & Breaking-Change Preflight (Stage 0)

Never upgrade any critical appliance (`UDM Pro`, `Synology NAS`, `prox`/`prox2`, `HAOS`, `Zigbee2MQTT`, `Authelia`, `DietPi` audio Pis) or multi-version jump blind:

1. **Run `cayco-preflight`** (`ssh prox /usr/local/sbin/cayco-preflight` or inspect open Renovate PRs in `cayco/home-network-automation` + HA `sensor.infrastruktura_przeglad_aktualizacji`).
2. **Fetch ALL Intermediate Changelogs (`v_installed .. v_target`)**:
   - When jumping multiple versions (e.g. `v1.2 -> v1.6`), inspect **every intermediate release**—never only `latest`!
   - For `UDM Pro` / UniFi APs & Switches, `Synology DSM`, `Proxmox VE` kernels, `DietPi`, and `Zigbee2MQTT`, use `search_web` to check community release threads for regressions affecting our hardware (`U7-Pro` 2.4 GHz `ABW-51n` IoT, `i915-sriov-dkms` on `i5-14500T`, `e1000e` on `NUC6i7KYK`, `ZBDongle-E` `1a86:55d4` `adapter: ezsp`).
   - Enforce the **72-hour soak window** (`>= 3 days` since upstream release) unless patching an actively exploited critical CVE.
3. **Run `ssh prox 'cayco-upgrade pre'`**:
   - Verifies Proxmox Quorum, Ever Rack UPS `OL` status, exports IoT JSON configs (`WLED`, `AWTRIX`, `Valetudo`), runs `/usr/local/sbin/backup-appdata-pbs.sh` (`pg_dumpall` + `.pxar` into deduplicated `pbs-local`), and captures the Checkmk Livestatus baseline.

## 2. Strict Dependency Execution Order & Checkmk Gates (Stages 1 -> 8)

Execute only the stages that have approved updates, and **run `ssh prox 'cayco-upgrade wait-green <hosts...>'` between EVERY stage** (halting immediately if any Checkmk check fails to turn `OK`):

1. **Stage 1 — Observer Alone**: `monitoring` (`Checkmk` on `dokerz` `VM 100`). Verify Checkmk API & local `pvecm_nodes` override before touching anything else.
2. **Stage 2 — Network Hardware (`Leaf -> Core -> Gateway`, One AP at a Time)**:
   - `AP Garaż` -> `AP góra` (`U6-LR`) -> Checkmk gate -> `AP dół` (`U7-Pro`) -> Checkmk gate -> leaf switches -> `Switch dół` (`USW-Pro-Max-24-PoE`; wait for all PoE clients + `prox` `bond0` to turn green!) -> export `.unf` backup -> `UDM Pro` (`10.0.0.1`) last.
3. **Stage 3 — Cluster, Storage & Hypervisor Backbone**:
   - Run **`ssh prox 'cayco-upgrade nas-prep'`** (`prox2-power wake && prox2-power hold` — **mandatory** before NAS reboot so `prox` + `prox2` retain `2/3` Quorum while `nas` `corosync-qnetd` reboots!).
   - Canary `prox2` + `pbs2` -> `CT 114 pbs` -> `Synology NAS` (`10.0.2.59`) -> wait for `3/3` Quorum & SMB mounts `OK` -> `prox` kernel (`cayco-upgrade prox-kernel-pin <kver>` verifies `i915-sriov-dkms` is `installed` and pins `--next-boot` so 1 power-cycle reverts any kernel panic!).
4. **Stage 4 — Identity, DNS, PKI & Edge Tunnel (Before Any OIDC App!)**:
   - `CT 105 adguard` -> `CT 117 pki` -> `CT 118 ingress-sso` (pre-validate `authelia validate-config` before stopping `authelia`!) -> `CT 110 vaultwarden` (`/usr/local/bin/update-vaultwarden`).
5. **Stage 5 — Upstream App Backends (`dokerz` & LXCs)**:
   - `cayco-upgrade snap 100` -> `dokerz` stacks (verify `qBittorrent WireGuard VPN and Killswitch` 5-layer check!) -> `CT 121 frigate` (must precede HA `custom_components/frigate`!) -> LXC apps (`112 paperless`, `119 mealie`, `120 bookorbit` checking JS `sed` targets, `102 archive`, `122 wrapvm`, `101 plex`, `107 loxone-llm`).
   - **`VM 104 music4home` rule**: OS `Debian-Security` patches ONLY (`cayco-upgrade snap 104`); **NEVER** upgrade MS4H `/opt/music_server` or `logitechmediaserver` (`apt-mark hold`).
6. **Stage 6 — Home Assistant (`VM 103 haos12.0` — `.2+` Core Releases Only, `Zigbee2MQTT` LAST!)**:
   - `cayco-upgrade snap 103` -> HACS integrations (note: `custom_components/fordpass` stays untouched upstream via `fordpass_raptor_fix` sidecar!) -> `MariaDB` -> `EMQX` -> `NUT` -> `HA Core (.2+)` -> `HAOS` reboot -> **`Zigbee2MQTT` (`45df7312_zigbee2mqtt`) updated/restarted LAST** once `EMQX` and `HA Core` are online!
   - Run **`ssh prox 'cayco-upgrade ha-z2m-verify'`** (asserts `binary_sensor.zigbee2mqtt_bridge_connection_state == 'on'` + `<60s` live router packet; auto-restarts Z2M / `usbreset 1a86:55d4` if `ZBDongle-E` `ezsp` UART desynced) + `wait-green homeassistant prox`.
7. **Stage 7 — Critical DietPi Audio Boards & Physical Appliances**:
   - **`gora-pi` (`10.0.2.13`) -> 24h soak -> `dol-pi` (`10.0.2.148`)**: Both are SD-card **DietPi** boards. Use **`dietpi-backup 1`** (to NAS) + **`dietpi-update 1`** ONLY (never `unattended-upgrades` or raw `apt upgrade`). Verify Checkmk `Multi-Room Audio Pi` + Squeezelite TTS.
   - **Appliances**: Run **`ssh prox 'cayco-upgrade valetudo'`** to automatically upgrade Valetudo vacuums (`Mietek` `10.0.6.89` -> `Mopek` `10.0.6.123` via `/api/v2/updater`, SHA256-verified, docked & `>=40%` battery only — never Xiaomi/Dreame vendor OTA!); `Tedee Bridge -> Lock` (daytime at home), `Prusa MK4` (idle, keep `.bbf` on USB), `EcoFlow DELTA 3` (daytime when `Ever UPS == 100% OL`).
8. **Stage 8 — Mark Complete & Sync Docs**:
   - Call `script.oznacz_przeglad_aktualizacji_wykonany` in Home Assistant, update Obsidian + `cayco/home-network-automation`, and let `cayco-upgrade hygiene` auto-prune `pre-upg` snapshots at `24h` (only if Checkmk is `OK`) and Docker layers at `48h`.
