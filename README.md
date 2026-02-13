# Tricky Addon Enhanced

[![Version](https://img.shields.io/badge/version-v4.9--auto-orange?style=flat-square)](https://github.com/Enginex0/tricky-addon-enhanced/releases)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue?style=flat-square)](https://www.gnu.org/licenses/gpl-3.0)
[![Magisk](https://img.shields.io/badge/Magisk-20.4%2B-00AF9C?style=flat-square&logo=magisk)](https://github.com/topjohnwu/Magisk)
[![KernelSU](https://img.shields.io/badge/KernelSU-32234%2B-green?style=flat-square)](https://kernelsu.org/)
[![APatch](https://img.shields.io/badge/APatch-11159%2B-purple?style=flat-square)](https://github.com/bmax121/APatch)

**Pass Play Integrity without lifting a finger.** 4-source keybox failover, automatic security patches, VBHash spoofing, and attestation engine health monitoring — all running silently in the background.

> Enhanced fork of [KOWX712's Tricky Addon](https://github.com/KOWX712/Tricky-Addon-Update-Target-List). Not affiliated with TrickyStore or TEESimulator — do not report issues there.

---

## Features

### Intelligent Keybox Management

Stop hunting for valid keyboxes. The module automatically fetches from 4 sources with intelligent failover:

| Priority | Source | Status |
|:--------:|--------|--------|
| 1 | Yurikey | Primary |
| 2 | Upstream KOWX712 | Fallback |
| 3 | IntegrityBox | Secondary fallback |
| 4 | Bundled | Offline backup |

- Validates XML structure before applying
- Backs up existing keybox automatically
- Respects custom keyboxes (set `keybox_source=custom` to protect yours)
- Configurable fetch interval (default: 5min)

### Security Patch Automation

Automatically detects your attestation engine variant and updates security patch dates:

| Variant | Detection | Config Location |
|---------|-----------|-----------------|
| James Fork | `James` in module.prop | `devconfig.toml` |
| Standard (TEESimulator / TrickyStore) | versionCode >= 158 or TEESimulator detected | `security_patch.txt` |
| Legacy | Fallback | resetprop |

Sets all three dates (system, boot, vendor) on boot and daily thereafter.

### VBHash Spoofing

Appear as a locked bootloader device. VBHash captured at install time with zero detection surface:

**Install Time (primary):**
- Reads `ro.boot.vbmeta.digest` directly from bootloader property — instant, zero dependencies
- Persists to `/data/adb/boot_hash` before any modules are active

**Subsequent Boots:**
- Reads from persisted file only (no extraction needed)

**Fallback chain** (if boot_hash missing):
1. Re-reads bootloader property
2. Last resort: temporary APK extracts via KeyStore attestation (camouflaged package name, removed immediately)

**15 properties spoofed:**
- `ro.boot.vbmeta.device_state` = locked
- `ro.boot.verifiedbootstate` = green
- `ro.boot.veritymode` = enforcing
- `ro.boot.vbmeta.digest` = (extracted)
- And 11 more vendor/boot properties

### Attestation Engine Health Monitor

Background supervisor ensures your attestation engine stays alive:

- Polls every 10s, detects TEESimulator or TrickyStore automatically
- 5s grace period for the engine's internal restart loop
- If still dead, restarts `service.sh` for full recovery
- Restart count tracked in `/data/adb/tricky_store/.health_state`
- WebUI health banner shows live status (green/red/orange indicator)

### Live Status Monitor

Module manager shows real-time status directly in the module description:

```
⚡ 37 Apps │ 🔑 Yurikey │ 🛡️ 2026-01-05 │ 🔒 VBHash
```

Updates every 30s — app count, keybox source, security patch level, and VBHash state at a glance.

### Modern WebUI

Zero-Mount inspired design with glass morphism aesthetics:

- AMOLED-friendly dark gradient (`#0F0F1A` to `#1A1A2E`)
- 6 accent color presets with random selection on launch
- Health status banner with live engine state
- Target list auto-refreshes every 3s
- Automation settings bottom sheet
- 23 languages with RTL support

### Set It and Forget It

A native supervisor binary manages all 5 background processes — if any die, they restart within 1s:

- **App Watcher:** Auto-adds new installations to target.txt
- **Xposed Detection:** Auto-excludes Xposed modules
- **Health Monitor:** Auto-restarts attestation engine on crash
- **Status Monitor:** Live module description updates
- **Conflict Detection:** Warns about 19 conflicting modules
- **Log Rotation:** 1MB limit with automatic cleanup

---

## Compatibility

| Root Manager | Minimum Version | WebUI Support |
|--------------|-----------------|---------------|
| **Magisk** | 20.4+ | [KSUWebUIStandalone](https://github.com/5ec1cff/KSUWebUIStandalone) or [WebUI-X](https://github.com/5ec1cff/WebUI-X) required |
| **KernelSU** | 32234+ | Built-in |
| **APatch** | 11159+ | Built-in |

**Requires:** [TEESimulator](https://github.com/JingMatrix/TEESimulator) or [TrickyStore](https://github.com/5ec1cff/TrickyStore) installed

> **Recommended:** Our [TEESimulator fork](https://github.com/Enginex0/TEESimulator) includes 7 stability and security fixes ([#119](https://github.com/JingMatrix/TEESimulator/pull/119) merged upstream) — attestation leak protection, restart resilience, and certificate fingerprint corrections.

---

## Installation

1. Download the [latest release](https://github.com/Enginex0/tricky-addon-enhanced/releases/latest)
2. Install via your root manager
3. Reboot

During install, press **Vol-** for manual target mode (GMS/GSF only) or **Vol+** / wait 10s for full automation.

The module automatically:
- Captures VBHash from bootloader property
- Builds exclude list from Xposed modules
- Generates initial target.txt
- Starts all background daemons
- Fetches a valid keybox

---

## Configuration

Edit `/data/adb/tricky_store/enhanced.conf`:

| Key | Default | Description |
|-----|---------|-------------|
| `keybox_enabled` | `1` | Enable auto keybox fetching |
| `keybox_source` | `yurikey` | Primary source (`yurikey`, `upstream`, `integritybox`, `custom`) |
| `keybox_interval` | `300` | Seconds between fetch attempts |
| `keybox_fallback_enabled` | `1` | Try secondary sources on failure |
| `security_patch_auto` | `1` | Enable auto patch updates |
| `security_patch_interval` | `86400` | Seconds between patch checks |
| `conflict_check_enabled` | `1` | Check for conflicting modules |
| `vbhash_enabled` | `1` | Enable VBHash spoofing |
| `automation_target_enabled` | `1` | Enable auto target.txt population |

Configuration is preserved across reinstalls and engine switches.

---

<details>
<summary><strong>CLI Reference</strong></summary>

All endpoints via `sh /data/adb/modules/TA_utl/common/get_extra.sh`:

| Endpoint | Purpose |
|----------|---------|
| `--get-config` | Read enhanced.conf |
| `--set-config KEY VALUE` | Update config value |
| `--set-custom-keybox` | Mark keybox as custom (skip auto-fetch) |
| `--fetch-keybox-now` | Trigger manual keybox fetch |
| `--set-security-patch-now` | Trigger manual patch update |
| `--security-patch` | Set patch dates from system |
| `--get-security-patch` | Fetch latest Android patch |
| `--tee-status` | Check attestation engine health |
| `--xposed` | Scan for Xposed modules |
| `--check-conflicts` | Run conflict detection |

</details>

<details>
<summary><strong>File Locations</strong></summary>

```
/data/adb/tricky_store/
├── enhanced.conf              # Module configuration
├── target.txt                 # Apps to protect
├── keybox.xml                 # Current keybox
├── security_patch.txt         # Patch dates (standard variant)
├── .health_state              # Health monitor state
├── .automation/               # Internal state (PIDs, exclude patterns)

/data/adb/Tricky-addon-enhanced/logs/
├── boot.log                   # Boot-time operations
├── main.log                   # General operations + watcher + health
└── conflict.log               # Conflict detection

/data/adb/boot_hash            # Persisted VBHash
```

</details>

<details>
<summary><strong>Troubleshooting</strong></summary>

**Check daemon status:**
```bash
sh /data/adb/modules/TA_utl/common/automation.sh --status
```

**Check attestation engine health:**
```bash
sh /data/adb/modules/TA_utl/common/get_extra.sh --tee-status
```

**View logs:**
```bash
cat /data/adb/Tricky-addon-enhanced/logs/boot.log
cat /data/adb/Tricky-addon-enhanced/logs/main.log
```

**Manual keybox fetch:**
```bash
sh /data/adb/modules/TA_utl/common/keybox_manager.sh --fetch
```

**Force VBHash extraction:**
```bash
sh /data/adb/modules/TA_utl/common/vbhash_manager.sh --extract
```

</details>

---

## Comparison with Upstream

| Feature | Upstream | Enhanced |
|---------|:--------:|:--------:|
| Keybox source | Single | 4-source failover |
| Keybox refresh | Manual | Auto (5min default) |
| Security patch | Manual | Auto on boot + daily |
| Custom keybox protection | Overwrites | Protected (`source=custom`) |
| VBHash spoofing | None | 15 properties |
| Attestation engine monitor | None | Auto-restart on crash |
| Live status in module manager | None | Real-time description |
| Conflict detection | None | 19 modules detected |
| WebUI design | Basic | Glass morphism, 23 languages |
| Logging | Limited | Unified system with rotation |
| Config persistence | Overwritten on update | Preserved across reinstalls |

---

## Conflict Detection

The module detects and handles conflicting modules:

**Auto-removed (16):** Yurikey, xiaocaiye, safetynet-fix, vbmeta-fixer, playintegrity, integrity_box, SukiSU_module, Reset_BootHash, Tricky_store-bm, Hide_Bootloader, ShamikoManager, extreme_hide_root, Tricky_Store-xiaoyi, tricky_store_assistant, extreme_hide_bootloader, wjw_hiderootauxiliarymod

**Blocks install (1):** Yamabukiko (aggressive conflict)

**Warning only (2):** com.lingqian.appbl, com.topmiaohan.hidebllist

---

## Credits

- **[@KOWX712](https://github.com/KOWX712)** — Original Tricky Addon
- **[@Enginex0](https://github.com/Enginex0)** — Enhanced fork maintainer
- **[@JingMatrix](https://github.com/JingMatrix)** — TEESimulator
- **[TS-Enhancer-Extreme](https://github.com/XtrLumen/TS-Enhancer-Extreme)** — VBHash extraction concept
- **[Yurikey](https://github.com/Yurii0307/yurikey)** — Primary keybox source
- **[Integrity-Box](https://github.com/MeowDump/Integrity-Box)** — Secondary keybox source
- **[TrickyStore](https://github.com/5ec1cff/TrickyStore)** — Original attestation module
- **[Zero-Mount](https://github.com/Enginex0/zeromount)** — WebUI design inspiration

---

## License

GPL-3.0. See [LICENSE](LICENSE) for details.

---

<p align="center">
<sub>This module is provided "as is" without warranty. Use at your own risk.</sub>
</p>
