# OLAX M100 API — capture & driver spec

The OLAX M100 runs **ZTE-lineage firmware**. Its admin page is a JavaScript app that calls an
on-device HTTP/JSON RPC API. This file is the source of truth for the `OlaxM100Client` driver.

> **Phase 0 is a manual step you do once with a laptop + browser DevTools.** Fill in every
> `TODO/CONFIRM` below from your own unit's traffic. The default recipes in code are best-effort
> guesses from documented ZTE behaviour and must be verified here.

## 0. Basics

| Field | Value (VERIFIED on a real unit, 2026-07-11) |
|---|---|
| Admin IP | **`192.168.8.1`** |
| `Server` response header | **`Demo-Webs`** (same firmware family as ZTE M30S Pro) |
| Firmware (`cr_version`) | `M100LSW1.1_FI_OLAX_SL_V01.01.02P42U28_07` (== `wa_inner_version`) |
| Dialect | **`reqproc`** — `/reqproc/proc_get` + `/reqproc/proc_post`. (goform 404s.) |
| `GET /` | `302 → /index.html` |

## 1. How to capture (do this first)

1. Join the M100's WiFi from a laptop. Open the admin UI in Chrome/Firefox.
2. Open **DevTools → Network**, filter **Fetch/XHR**, tick "Preserve log".
3. Log in. For each request note: **method**, **URL + query**, **request headers**
   (`Referer`, `Cookie`), **form body**, **response JSON**.
4. Right-click a request → **Copy as cURL** to preserve the exact bytes.
5. Click through every feature and record the `cmd=` (reads) and `goformId=` (writes).

## 2. Login handshake — CONFIRM THE EXACT RECIPE

**VERIFIED for this M100** (the LD challenge is disabled — `cmd=LD` returns `{"LD":""}`):

- [x] Version probe: `GET /reqproc/proc_get?isTest=false&cmd=Language,cr_version,wa_inner_version&multi_data=1`
- [x] LD token: `GET /reqproc/proc_get?isTest=false&cmd=LD` → **`{"LD":""}`** (empty → no challenge)
- [x] Password digest: **`base64(password)`** (plain, no hashing).
      e.g. password `hunter2` → `aHVudGVyMg==` (example only — never commit a real password)
- [x] Login write: `POST /reqproc/proc_post` body `isTest=false&goformId=LOGIN&password=<base64>`
      — **no `AD` token needed for login** (verified accepted without it).
- [x] Success shape: **`{"result":"0"}`**; wrong password/format → `{"result":"3"}`.
- [x] Session: **no cookie is set.** Login succeeds with `{"result":"0"}` and no
      `Set-Cookie`; the session is bound to the **client IP**, so every request from
      the same device is authenticated. `cmd=loginfo` returns `"ok"` once logged in
      (drives `isLoggedIn()`).

`lib/core/crypto.dart` + `ZteApiTransport.login()` already take the empty-LD → base64 path.

## 3. AD anti-CSRF token — NOT USED

**This firmware has no `AD`/`RD` token.** Reading the device JS (`js/com.js`), every POST is
built as plain `{goformId, ...params}` and sent to `/reqproc/proc_post` — there is no hash
parameter. `ZteConfig.reqproc` sets `useAd: false`. A correct `Referer` header is still sent.

## 4. Read commands (`cmd=`) — VERIFIED

Multi-reads use `GET /reqproc/proc_get?isTest=false&multi_data=1&cmd=a,b,c`. All values come back
as strings; empty string `""` means "not populated on this model".

| Feature | `cmd=` value(s) | Notes |
|---|---|---|
| Signal / network | `network_type`, `sub_network_type`, `rssi`, `lte_rsrp`, `nv_rsrq`, `nv_sinr`, `lte_band`, `cell_id`, `signalbar`(0–5), `network_provider` | `sub_network_type`=`FDD_LTE`; `signalbar` drives the bars; `lte_band` e.g. `3` |
| Device / About | `imei`, `sim_imsi`(imsi), `ziccid`(iccid), `msisdn`(phone), `cr_version`(fw), `hw_version`, `lan_ipaddr`, `lan_netmask`, `LocalDomain`, `MAX_Access_num`, `dhcpEnabled`, `dhcpStart`, `dhcpEnd`, `dhcpLease_hour` | `imsi`/`mac_address` empty — use `sim_imsi` |
| Counts / badges | `sms_unread_num`, `sta_count`, `pin_status` | drive the SMS badge + device count |
| Link / SIM | `ppp_status`(`ppp_connected`…), `modem_main_state`(`modem_init_complete`=ready), `simcard_roam`(`Home`/`Roaming`) | `sim_status` is empty — use `modem_main_state` |
| Battery | `battery_pers`(**0–4 bar LEVEL, not a %**), `battery_charging`(0/1), `battery_vol_percent`(true %, **empty** on M100) | Firmware maps `battery_pers`→icon: 1=power_one…4=power_full, 0/empty=power_out (charging→power_charging.gif). So `3` = 3/4 bars ≈ 75%, **not 3%**. `battery_value` also empty. Approximate percent = level ÷ 4 × 100. |
| Data usage | `realtime_tx_bytes`,`realtime_rx_bytes`,`realtime_time`,`realtime_tx_thrpt`,`realtime_rx_thrpt`,`monthly_tx_bytes`,`monthly_rx_bytes` | `*_thrpt` = live B/s |
| WiFi config | `SSID1`,`WPAPSK1_encode`(base64 of key),`WPAPSK1`(plaintext key),`AuthMode`(`WPA2PSK`),`EncrypType`(`AES`),`HideSSID`,`m_ssid_enable`(guest),`MAX_Access_num`,`wifi_band`(`b`=2.4GHz) | **`WPAPSK1_ENCRYPT` is always empty — read `WPAPSK1_encode` and base64-decode it** (or `WPAPSK1`). `security_mode`/`cipher` read back empty; derive `cipher` from `EncrypType` on write. |
| Connected devices | `station_list` (single cmd, **no `multi_data`**) → `[{hostname, ip_addr, mac_addr, dev_type, ip_type, connect_time}]`. `lan_station_list` is a separate, empty list on this model. | `hostname` here is the **DHCP name**. Names set via `EDIT_HOSTNAME` are stored separately in `cmd=hostNameList` → `{devices:[{mac, hostname}]}`; **overlay it onto `station_list` by MAC** (custom name wins) or renames won't show. |
| Data plan | `data_volume_limit_switch`(0/1),`data_volume_limit_unit`(`data`/`time`),`data_volume_limit_size`,`data_volume_alert_percent`,`monthly_time` | Off by default on this unit. |
| SMS list | `sms_data_total` + `page`,`data_per_page`,`mem_store=1`,`tags=10`,`order_by=order by id desc` → `{messages:[{id,number,content,tag,date,draft_group_id}]}` | **`content` is UTF-16BE hex**; `tag` 0=read,1=unread,2=sent,3=draft,4=fail; `date`=`yy,MM,dd,HH,mm,ss,+tz`(tz in 15-min units); `id` is monotonic. The stock UI (and this app) **group by `number` into conversations** — sent messages thread by recipient. |
| SMS capacity | `sms_capacity_info` → `sms_nv_total`/`sms_nv_rev_total`/`sms_nv_send_total`/`sms_nv_draftbox_total` (device NV) + `sms_sim_*` (SIM) | Drives the "Device 10/20 · SIM 0/50" header. |
| SMS settings | `sms_parameter_info` → `sms_para_sca`(SMS center, e.g. `+8801801000004`), `sms_para_validity_period`, `sms_para_status_report`, `default_store`(`nv`) | |

## 5. Write commands (`goformId=`) — VERIFIED (POST /reqproc/proc_post)

| Action | `goformId=` | Params |
|---|---|---|
| Login | `LOGIN` | `password=base64(pw)` (`PASSWORD_ENCODE`), no AD |
| Logout | `LOGOUT` | — |
| Send SMS | `SEND_SMS` | `Number`, `sms_time`(`yy;MM;dd;HH;mm;ss;+tz`), `MessageBody`(UTF-16BE hex), `ID=-1`, `encode_type=UNICODE`, `notCallback=true` |
| Delete SMS | `DELETE_SMS` | `msg_id=<id;id;>` |
| Delete all SMS | `ALL_DELETE_SMS` | `which_cgi=<mem>` |
| Mark read | `SET_MSG_READ` | `msg_id=<id;>`, `tag=0` |
| Set WiFi | `SET_WIFI_SSID1_SETTINGS` | `ssid`, `broadcastSsidEnabled`(1=visible), `MAX_Access_num`, `security_mode`(=AuthMode), `cipher`, `NoForwarding`, `show_qrcode_flag`; **for WPA modes also** `security_shared_mode`(=cipher) + **`passphrase`=base64(key)**. ⚠️ The password rides in **`passphrase`, NOT `WPAPSK1`** (that param is ignored — the old cause of "password never changes"). `cipher`: TKIP→`0`, AES→`1`, both→`2`. WPA modes needing a passphrase: `WPAPSK`,`WPA2PSK`,`WPAPSKWPA2PSK`,`WPA3Personal`,`WPA2WPA3`. |
| Mobile data on/off | `CONNECT_NETWORK` / `DISCONNECT_NETWORK` | `notCallback=true`; reply `{"result":"success"}`. Toggles only the cellular WAN — the LAN/WiFi stays up. |
| Rename device | `EDIT_HOSTNAME` | `mac`, `hostname` |
| Power off | `TURN_OFF_DEVICE` | — |
| Factory reset | `RESTORE_FACTORY_SETTINGS` | — (wipes all settings incl. admin password) |
| Send USSD | `USSD_PROCESS` | `USSD_operator=ussd_send`, `USSD_send_number=<code>` (reply: `USSD_reply_number`; cancel: `USSD_operator=ussd_cancel`). **Poll `cmd=ussd_write_flag` BY ITSELF** (not combined with other cmds in one multi-read — verified live that combining always returns the reply fields empty). `"15"`=still waiting (keep polling); `"16"`=done — THEN fetch `cmd=ussd_data_info` **alone** → `{ussd_data(hex), ussd_action, ussd_dcs}` (note: response field is `ussd_data`, not `ussd_data_info` — that's just the query's cmd name). Any other flag is terminal/failure: `1`=no service, `2`=network terminated, `3`/`4`/`unknown`=timeout, `10`=busy/retry, `41`=operation not supported, `99`=unsupported by network. |
| Reboot | `REBOOT_DEVICE` | — (also `TURN_OFF_DEVICE`, `RESTORE_FACTORY_SETTINGS`) |
| Band lock | `SET_FREQ_BAND` / `SET_NETWORK` / `SET_BEARER_PREFERENCE` | not yet wired in-app |
| APN | `APN_PROC_EX` | `apn_mode`, `apn_action`, `profile_name`, `wan_apn` |
| PIN | `ENTER_PIN`/`ENTER_PUK`/`ENABLE_PIN`/`DISABLE_PIN` | |

Full goformId inventory (from `js/*.js`) also includes firewall/port-forward, DHCP, DDNS, DMZ,
UPnP, URL filter, HTTP file share, phonebook (`PBM_CONTACT_*`), and network scan/connect —
available to wire up as future features.

### ⚠️ USSD is disabled on this M100 firmware build — confirmed, not a client bug

The polling algorithm above is correct (fixed 2026-07-11: the old code combined
`ussd_write_flag`/`ussd_action`/`ussd_data_info` into one multi-read, which the firmware **always**
answers with the reply fields empty — they only populate when `ussd_data_info` is queried
*alone*). But on this exact unit/firmware (`M100LSW1.1_..._V01.01.02P42U28_07`), sending **any**
USSD code — three different carrier-documented ones tried (`*123#`, `*222#`, and the carrier's own
`*১#`/`*1#` balance-check code straight from an SMS) — always resolves to `ussd_write_flag=99`
(`ussd_unsupport`). Three independent signals confirm this is a genuine firmware/hardware
limitation, not a request-shape or carrier issue:

1. **The device's own capability config says so.** `GET /js/set.js` (fetched live from the router,
   not a guess) contains the literal key `HAS_USSD:false`.
2. **The stock web UI has no USSD page anywhere.** Checked every nav level: top bar (`SMS |
   Phonebook | Advanced Settings | Quick Settings`), Advanced Settings (`Power-save | Router |
   Firewall | Update | IMEI/TTL | Others`), SMS (`Device | SIM Card | Settings`) — none of them
   expose USSD. `com.js` reads `hasUssd = <config>.HAS_USSD` and gates the (nonexistent-on-this-
   build) USSD page behind it.
3. **Capability flags like `HAS_USSD`/`HAS_SMS`/`HAS_WIFI` are NOT exposed via the JSON API at
   all** — `GET cmd=HAS_USSD,HAS_SMS,HAS_WIFI` all return empty strings, even for features that
   demonstrably work (SMS, WiFi). So the app cannot query this capability at runtime; it only
   lives in the static `js/set.js` asset the browser UI loads, which a mobile client has no
   business depending on.

**Takeaway:** `OlaxM100Client.sendUssd` throws a clear, accurate `CommandFailedException` on flag
`99` explaining this is a firmware limitation (not "try a different code" or "check your signal").
Don't try to "fix" USSD further on this exact firmware build — there's no request-parameter
workaround for a feature the vendor disabled. If a *different* M100 firmware/region build ever
turns out to have `HAS_USSD:true`, the existing poll logic should work for it unchanged since it
implements the firmware's own algorithm faithfully.

## 6. Raw fixtures

Paste real JSON responses into `test/fixtures/` (one file per command) so the parser has
regression coverage. Redact IMEI/IMSI/phone numbers before committing.
