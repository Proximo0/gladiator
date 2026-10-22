# EOS setup and first test (owner's Windows PC)

Sandblood's online backend is Epic Online Services through the **EOSG** plugin (Epic Online Services Godot, version
**2.3.1**, github.com/3ddelano/epic-online-services-godot). The code (`game/net/service_eos.gd`) is in the repo; the
plugin binaries and your credentials are not. Without either, the game quietly uses the LAN backend (`ServiceLocal`),
so nothing breaks on machines that do not have them. How the backend maps to EOS: `docs/online_service.md`.

## 1. Install the plugin

1. Download **`epic-online-services-godot-all.zip`** (or the Windows-only zip) from the **2.3.1** release:
   https://github.com/3ddelano/epic-online-services-godot/releases/tag/2.3.1
2. Unzip it and copy its `addons/epic-online-services-godot/` folder to `<project>/addons/epic-online-services-godot/`
   (create `addons/` if needed). You should then have `addons/epic-online-services-godot/eos.gd`, `heos/`,
   `eosg.gdextension` and `bin/windows/libeosg.windows.template_debug.dev.x86_64.dll` plus `EOSSDK-Win64-Shipping.dll`.
3. Open the project in the Godot 4.7.2 editor. Ignore the `sample/` folder of the zip; only `addons/` is needed.
4. **Project > Project Settings > Plugins**: tick **Epic Online Services Godot 4.2+ (EOSG)**. This adds the autoloads
   `EOSGRuntime`, `HPlatform`, `HAuth`, `HAchievements`, `HFriends`, `HStats`, `HLeaderboards`, `HLobbies`, `HP2P`,
   `HSessions` to `project.godot`. ServiceEos needs `EOSGRuntime`, `HPlatform`, `HAuth` and `HLobbies`.
5. **Restart the editor** (the GDExtension loads at start).

Git: the addon (`addons/epic-online-services-godot/`) and `config/eos_credentials.cfg` are git-ignored on purpose (EOS SDK
binaries stay out of the public repo), and the committed `project.godot` has no EOSG autoloads or `[editor_plugins]` entry:
CI and headless Linux runs have no plugin binaries (the bundled addon is Windows-only), and a project with the autoloads
but no binaries prints autoload parse errors at start. Scripted and headless runs never pick EOS (`--online-service=auto`),
so tests and sims stay on the LAN backend. Do not commit the autoload lines the editor writes when you tick the plugin
(step 4); for a Windows build with EOS use the build script in section 1b instead, which enables the plugin in a copy.

## 1b. Build a Windows .exe with EOS (no editor needed)

With the addon unzipped in place (step 2 above) and `config/eos_credentials.cfg` written (section 3), run from the
project folder (Windows Git Bash or WSL need `godot` on the PATH; on the cloud box it already is):

```
tools/export_eos_windows.sh
```

It copies the repo to `build/eos_src`, adds the credentials there, writes the plugin's autoloads and
`[editor_plugins]` entry into that copy's `project.godot`, runs `godot --import`, exports the "Windows Desktop" preset
(release, embedded pack) and zips `build/eos_windows/` to **`build/SandbloodEOS-windows.zip`** (log:
`build/eos_export.log`; the Linux "dynamic library not found" and `IEOS` parse errors in it are expected, because only the
Windows DLLs exist). It needs the Windows export templates (`tools/export_windows.sh` downloads them once). The zip holds
`Sandblood.exe`, `libeosg.windows.template_release.x86_64.dll`, `EOSSDK-Win64-Shipping.dll`, `xaudio2_9redist.dll`
(all next to the exe, where Godot looks for exported GDExtension libraries), `eos_credentials.cfg`, and the `.bat`
launchers. Keep all files together; the zip contains your client secret, so do not post it publicly.
`tools/export_windows.sh` (no EOS, no plugin) still builds the plain LAN-only zip.

## 2. Portal (dev.epicgames.com/portal, your Sandblood product)

Work in the **Dev** sandbox and its deployment first.

1. **Stats** (Game Services > Stats > Create stat; all integer):

   | Name | Aggregation |
   | --- | --- |
   | `sb_rating` | **Latest** |
   | `sb_games` | **Sum** |
   | `sb_wins` | **Sum** |
   | `sb_losses` | **Sum** |

2. **Leaderboard** (Game Services > Leaderboards > Create): ID **`sb_rating_all`**, stat `sb_rating`, aggregation
   **Latest**, no start or end date (all time). Rows rank highest first.
3. **Client policy** (Product Settings > Clients > Client Policies > Add new): name it "Sandblood game client", policy type
   **Custom**, **User required** on (Connect device-id users count as users). Allow only:
   - **Lobbies**: create, join, update, leave, destroy, search (all lobby actions for the local user).
   - **P2P**: allowed (needed for the relay).
   - **Stats**: find stats for the local user **and ingest for the local user** (Tier 0 writes its own stats; a later
     server verifier would take ingest away from the client).
   - **Leaderboards**: find definitions, find ranks, find user scores.
   Leave Epic account (Auth), Ecom, Achievements, Anti-Cheat, Friends, Presence, Player/Title Storage and Sanctions off.
4. **Client** (Product Settings > Clients > Add new client): name "Sandblood game", policy = the one above. Copy its
   **Client ID** and **Client Secret**.
5. **Identity provider / Connect**: the game signs in with EOS Connect **Device ID** (no Epic account, no login screen).
   If your portal lists identity providers per deployment (Product Settings > Identity Providers, or Game Services >
   Connect), make sure **Device ID** is enabled for the Dev deployment. Nothing else (Steam, Epic, Apple) is needed.
6. Note the **Product ID** (Product Settings), **Sandbox ID** (Sandboxes, the Dev one) and **Deployment ID** (that
   sandbox's deployment).

## 3. Credentials file

Create `config/eos_credentials.cfg` in the project (it is git-ignored; never commit it):

```ini
; Sandblood EOS credentials, Dev sandbox. Quotes are optional.
[eos]
product_id = "..."
sandbox_id = "..."
deployment_id = "..."
client_id = "..."
client_secret = "..."
; optional
; product_name = "Sandblood"
; product_version = "0.1.0"        ; default: application/config/version, else "dev"
; encryption_key = "<64 hex characters, only for Player/Title Storage, unused now>"
```

The game looks for it at `res://config/eos_credentials.cfg`, then `eos_credentials.cfg` next to the executable, then
`user://eos_credentials.cfg`. `tools/export_windows.sh` copies it next to `Sandblood.exe` when it exists (so the zip
contains it). An Android build needs it inside the pack: add `include_filter="config/eos_credentials.cfg"` to the
Android preset in `export_presets.cfg` (the export script warns when it is missing). The client secret ships with the
game either way: it only names the client policy, which is why the policy allows nothing dangerous.

## 4. First run

Run from the editor (F5) or `godot --path .`. Open **Quick Match**: the status line should read "Connecting to Epic
Online Services", then "Signed in as <name>", then "Searching Epic Online Services". The leaderboard footer says
"EOS: all players". If the game shows a LAN search instead, the plugin or the credentials were not found; run with
`-- --online-service=eos` and the reason is printed as a warning in the Output panel. The EOS SDK's own log goes
through `HPlatform` (set `HLog.log_level` in the editor's remote tree or add a line in a debug script to see it).

## 5. Test plan on one PC: two instances quick-matching through EOS

The second instance needs a second identity. `--eos-profile=<name>` gives it its own EOS cache folder
(`user://eosg-cache-<name>`) and its own local profile (`user://eos_profile_<name>.json`).

1. Built game (easiest): unzip `SandbloodEOS-windows.zip` anywhere, double-click **`Sandblood.exe`** (instance 1), then
   double-click **`Sandblood (2nd player test).bat`** (instance 2, which runs `Sandblood.exe -- --eos-profile=p2`).
   From the editor instead: **Debug > Customize Run Instances...**, enable multiple instances, **2** instances; instance 1
   with no arguments, instance 2 with launch arguments `-- --eos-profile=p2` (needs the plugin ticked, step 4 of section 1).
2. Give the two players different names on the Online screen.
3. **Quick Match on both** within a few seconds. Expected: one says "Waiting for an opponent" (it hosts), the other
   "Joining <name>"; both then show the other's name and rating; the host's lobby goes invite-only; the fight starts.
   If both host for a moment, the one with the larger EOS id gives up its lobby and joins the other within ~3 s.
4. Fight to the end. Expected: both result screens show the same winner and the rating change (+N on one, -N on
   the other) once both reports are in (up to 20 s if one is slow). In the portal (Game Services > Stats / Leaderboards, player lookup) the two
   ProductUserIds have `sb_games` 1 and `sb_rating` of the new ratings.
5. Open **Leaderboard** on both: both players listed with their display names, rating, tier, W-L.
6. Edge cases, one at a time:
   - Cancel while waiting: the waiting lobby disappears (a new search from the other instance finds nothing).
   - Leave mid-fight from the Esc menu: the leaver is rated a loss (`forfeit`), the other a win.
   - Close the client's window mid-fight: the host shows "disconnected"; the host's lone report rates after 20 s.
   - Quick Match alone: "Searching (rating window ±N)" widens; after 120 s "Nobody to fight right now".
   - `-- --online-service=local` on both: the old LAN path still works.
7. Relay check: the fight should feel the same as on LAN. To force the relay path (no direct connection), test from two
   machines on different networks (a phone hotspot); EOS relays are used automatically when a direct path fails.

**If instance 2 says "--eos-profile=p2 signed in as the same EOS user as the default profile"**: the EOS SDK keeps the
device id per Windows user, not per cache folder, on this machine. Run instance 2 as another Windows user
(`runas /user:<other user> "Sandblood.exe -- --eos-profile=p2"`, after creating a local user) or on a second PC.

## 6. Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| "Epic Online Services did not start" | Wrong product, sandbox, deployment or client id, or a sandbox/deployment mismatch. |
| "Could not create the EOS device id" | No network, or Device ID not enabled for the deployment. |
| "EOS sign-in failed" | Client policy missing, or the client not assigned to the deployment's policy. |
| Lobbies never found / "Could not open a lobby" | Lobby permissions missing from the client policy; both instances on different builds (`build_id` differs when data files or Tuning differ). |
| Result rated locally but stats unchanged in the portal | Stats ingest not allowed for the local user in the client policy (a warning names it in the log). |
| Leaderboard "unavailable (NotFound)" | `sb_rating_all` not created in this deployment, or no rated game yet. |
| Fight never starts after "Found" | P2P not allowed in the client policy, or a firewall blocking the game (allow it in Windows Defender Firewall). |

Android later: EOSG needs the Godot Android build template plus the EOS SDK `.aar` in `android/build/build.gradle`
(EOSG docs, "Initialization on Android"), and the credentials include filter above.
