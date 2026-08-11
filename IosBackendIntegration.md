# iOS App ↔ Backend Integration Summary

## Overview
This document describes how the KstApp iOS app integrates with the push notification backend server.

## Backend Server

### API Endpoints

#### PUT `/api/v1/user/:username`
Register or update user settings and start/stop notifications.

**Request Body:**
```json
{
  "on4kstUsername": "WA4YA",
  "on4kstPassword": "your-password",
  "gridSquare": "FN42KJ",
  "on4kstRoom": 6,              // Room index (0-20): 0=50/70MHz, 6=50 MHz IARU Region 2
  "notificationsEnabled": true,
  "notificationFilter": "all",  // or "myCallsign"
  "pushoverUserKey": "ub5yxykr6sy7q74hoiwbarg1s56m6r",
  "notificationService": "pushover"  // or "apns"
}
```

**Response:**
```json
{
  "message": "Notifications enabled for user WA4YA",
  "username": "WA4YA"
}
```

#### GET `/api/v1/user/:username/debug`
Get connection debug state for diagnostics.

#### POST `/api/v1/user/:username/test-pushover`
Send a test Pushover notification (bypasses ON4KST).

#### POST `/api/v1/user/:username/simulate-message`
Simulate an incoming ON4KST message to test the filter/push pipeline.

### ON4KST Chat Rooms
Room indices sent to backend (0-based):
| Index | Room Name |
|-------|-----------|
| 0 | 50/70 MHz |
| 1 | 144/432 MHz |
| 2 | Microwave |
| 3 | EME/JT65 |
| 4 | Low Band (160-80m) |
| 5 | 50 MHz IARU Region 3 |
| 6 | 50 MHz IARU Region 2 |
| 7 | 144/432 MHz IARU R 2 |
| 8 | 144/432 MHz IARU R 3 |
| 9 | kHz (2000-630m) |
| 10 | Warc (30,17,12m) |
| 11 | 28 MHz |
| 12 | 40 MHz |

### Notification Flow
1. iOS app calls `PUT /api/v1/user/:username` when user connects or changes settings
2. Backend creates ON4KST TCP connection, logs in, joins specified room
3. Backend monitors chat messages
4. When message arrives:
   - Filter is applied (`all` or `myCallsign`)
   - If filter matches, push notification sent via Pushover or APNs
5. User receives notification on phone

### Path Normalization
The backend now handles double-slash paths (`//api/v1/user/...`) that may be sent by iOS clients. A middleware normalizes these to single-slash paths.

## iOS App Integration

### BackendService
The `BackendService` class handles all communication with the backend.

**Key Methods:**
- `syncUserSettings(...)` - Syncs user settings to backend (called automatically)
- `updateBackendURL(_:)` - Updates the backend URL in UserDefaults

### KSTChatManager
The main chat manager coordinates backend sync:

**Triggers for Backend Sync:**
1. `connectChat()` - When user connects to ON4KST
2. Room change (`currentRoomIndex`) - Debounced by 0.5s
3. Notification settings change - Debounced by 0.5s
4. Grid square change - Debounced by 0.5s
5. Device token registration - After push registration

**Sync Parameters:**
```swift
BackendService.shared.syncUserSettings(
    username: username,
    password: password,
    gridSquare: myGridSquare,
    notificationsEnabled: notificationsEnabled,
    notificationFilter: notificationFilter.rawValue,
    deviceToken: deviceToken.isEmpty ? nil : deviceToken,
    pushoverUserKey: pushoverUserKey.isEmpty ? nil : pushoverUserKey,
    on4kstRoom: currentRoomIndex - 1,  // Convert to 0-based index
    notificationService: service
)
```

### UserDefaults Keys
| Key | Purpose |
|-----|---------|
| `KSTBackendURL` | Backend server URL (e.g., `http://192.168.1.126:3000`) |
| `KSTPushoverUserKey` | Pushover user key |
| `KSTDeviceToken` | APNs device token |
| `KSTUsername` | ON4KST username |
| `KSTPassword` | ON4KST password |
| `KSTRoomIndex` | Selected room (1-based) |
| `KSTGridSquare` | Maidenhead grid square |

### Fix Applied
**Issue:** iOS app was saving to `KSTBackendURL` but `BackendService.swift` was reading from `BackendURL`.

**Fix:** Updated `BackendService.swift` to use `KSTBackendURL` consistently.

## Testing

### Test Pushover Notification
```bash
curl -X POST http://localhost:3000/api/v1/user/WA4YA/test-pushover
```

### Test Message Simulation
```bash
curl -X POST http://localhost:3000/api/v1/user/WA4YA/simulate-message \
  -H "Content-Type: application/json" \
  -d '{"sender":"ON4KST","message":"Test message"}'
```

### Check Connection State
```bash
curl http://localhost:3000/api/v1/user/WA4YA/debug
```

## Troubleshooting

### App shows "A server with the specified hostname could not be found"
- Check that `KSTBackendURL` in UserDefaults matches your backend IP
- Ensure backend is running: `curl http://localhost:3000/health`
- Verify no firewall blocking port 3000

### Notifications not arriving
1. Check backend logs for connection status
2. Verify `debug` endpoint shows `isConnected: true`
3. Confirm Pushover key is valid (30 characters)
4. Test with `/test-pushover` endpoint

### Room not matching
- iOS app uses 1-based index (UI picker)
- Backend uses 0-based index (array)
- Conversion: `backendRoom = iOSRoom - 1`