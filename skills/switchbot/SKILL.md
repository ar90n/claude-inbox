---
name: switchbot
description: >
  This skill should be used when the user asks to "turn on the light",
  "turn off the AC", "open the curtain", "lock the door", "check room
  temperature", "list my devices", or needs to control any SwitchBot
  smart home device.
---

# SwitchBot

Control SwitchBot devices via the Web API (v1.1).

Requires `SWITCHBOT_TOKEN` and `SWITCHBOT_SECRET` environment variables
(from SwitchBot app > Profile > Preferences > Developer Options).

## Authentication

Every API call needs signed headers. Generate them with:

```bash
eval $(python3 -c "
import time,hashlib,hmac,base64,uuid,os
token=os.environ['SWITCHBOT_TOKEN']
secret=os.environ['SWITCHBOT_SECRET']
nonce=str(uuid.uuid4())
t=str(int(time.time()*1000))
sign=base64.b64encode(hmac.new(secret.encode(),f'{token}{t}{nonce}'.encode(),hashlib.sha256).digest()).decode()
print(f'export SB_HEADERS=(-H \"Authorization: {token}\" -H \"sign: {sign}\" -H \"t: {t}\" -H \"nonce: {nonce}\" -H \"Content-Type: application/json\")')
")
```

Headers expire quickly. Regenerate before each request.

## API

Base URL: `https://api.switch-bot.com/v1.1`

### List devices

```bash
curl -sf "${SB_HEADERS[@]}" https://api.switch-bot.com/v1.1/devices | jq .
```

Returns `body.deviceList` (physical) and `body.infraredRemoteList` (IR virtual).
Each device has `deviceId`, `deviceName`, `deviceType`.

Run this first to discover device IDs, then remember them for the session.

### Device status

```bash
curl -sf "${SB_HEADERS[@]}" "https://api.switch-bot.com/v1.1/devices/${DEVICE_ID}/status" | jq .
```

### Send command

```bash
curl -sf "${SB_HEADERS[@]}" -X POST \
  "https://api.switch-bot.com/v1.1/devices/${DEVICE_ID}/commands" \
  -d '{"command":"turnOn","parameter":"default","commandType":"command"}'
```

### Execute scene

```bash
# List scenes
curl -sf "${SB_HEADERS[@]}" https://api.switch-bot.com/v1.1/scenes | jq .

# Execute
curl -sf "${SB_HEADERS[@]}" -X POST \
  "https://api.switch-bot.com/v1.1/scenes/${SCENE_ID}/execute"
```

## Command Reference

### Physical Devices

| Device | Commands | Parameters |
|---|---|---|
| Bot | `turnOn`, `turnOff`, `press` | default |
| Plug / Plug Mini | `turnOn`, `turnOff` | default |
| Color Bulb | `turnOn`, `turnOff`, `setBrightness`, `setColor` | brightness: 1-100, color: `"255:128:0"` (R:G:B) |
| Strip Light | `turnOn`, `turnOff`, `setBrightness`, `setColor` | same as Color Bulb |
| Ceiling Light | `turnOn`, `turnOff`, `setBrightness`, `setColorTemperature` | brightness: 1-100, colorTemperature: 2700-6500 |
| Curtain / Curtain 3 | `turnOn`, `turnOff`, `setPosition` | position: `"0,ff,{0-100}"` (0=open, 100=closed) |
| Lock | `lock`, `unlock` | default |
| Humidifier | `turnOn`, `turnOff`, `setMode` | auto / 101-103 / 0-100 (%) |

### IR Virtual Devices (commandType: "customize")

For IR remotes learned in the SwitchBot app, use `commandType: "customize"`:

```bash
curl -sf "${SB_HEADERS[@]}" -X POST \
  "https://api.switch-bot.com/v1.1/devices/${DEVICE_ID}/commands" \
  -d '{"command":"turnOn","parameter":"default","commandType":"customize"}'
```

| Device | Commands |
|---|---|
| Air Conditioner | `setAll` with parameter `"{temp},{mode},{fan},{power}"` |
| TV / IPTV / STB | `turnOn`, `turnOff`, `SetChannel`, `volumeAdd`, `volumeSub` |
| Fan | `turnOn`, `turnOff`, `swing`, `lowSpeed`, `middleSpeed`, `highSpeed` |
| Light | `turnOn`, `turnOff`, `brightnessUp`, `brightnessDown` |

**Air Conditioner `setAll` parameter format:** `"{temp},{mode},{fan},{power}"`
- temp: temperature in celsius
- mode: 1=auto, 2=cool, 3=dry, 4=fan, 5=heat
- fan: 1=auto, 2=low, 3=medium, 4=high
- power: on/off

Example: `"26,2,1,on"` = 26°C, cool, auto fan, power on

## Workflow

1. Generate auth headers (see above)
2. `GET /devices` to list all devices (first time per session)
3. Match user's request to a device by name
4. `POST /devices/{id}/commands` to control it
5. Confirm the action to the user

## Error Handling

- Missing env vars: report that SwitchBot is not configured
- API error (statusCode != 100): report the error message
- Device not found: list available devices and ask user to clarify
