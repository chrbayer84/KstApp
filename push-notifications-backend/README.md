# KstApp Push Notification Backend

This is the backend service for delivering push notifications to the KstApp iOS application when the app is not active (in background or terminated). The backend connects to the ON4KST chat server, filters incoming messages based on user-defined notification criteria, and sends push notifications via Apple Push Notification service (APNs).

## Table of Contents
- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- ** [Setup](#setup)**
- [Configuration](#configuration)
- [Usage](#usage)
- [API Endpoints](#api-endpoints)
- [Project Structure](#project-structure)
- [Testing](#testing)
- [Deployment](#deployment)
- [Future Enhancements](#future-enhancements)

## Overview

This backend service provides push notification functionality for the KstApp iOS application. It maintains persistent TCP connections to the ON4KST chat server for each user who has enabled notifications, processes incoming messages, applies filtering rules, and sends push notifications via APNs or Pushover when appropriate.

The service is designed to run on a Raspberry Pi or any Node.js-capable device and provides a RESTful API for the iOS app to synchronize settings including ON4KST credentials, notification preferences, and push notification tokens.

## Features

- Persistent TCP connections to ON4KST server (www.on4kst.info:23000) per user
- Secure login to ON4KST using user-provided credentials
- Automatic room selection (defaults to 50/70 MHz)
- Periodic user list updates every 3 minutes via `/sh us` command
- Message parsing using the same format as the iOS client
- Notification filtering matching iOS app behavior:
  - `all`: Notify for every message
  - `myCallsign`: Notify only when message contains user's callsign in parentheses (case-insensitive)
- Push notifications via Apple Push Notification Service (APNs) **or** Pushover.net
- Secure HTTP API for settings synchronization
- Environment-based configuration
- Comprehensive test suite
- Graceful shutdown and reconnection handling

## Architecture

```
+-------------------+     HTTPS/WSS     +------------------+
|   KstApp (iOS)    | <--------------> | Notification Backend|
|                   |  (Settings Sync)  |   Service        |
+-------------------+                  +--------+---------+
                                              |
                                   TCP Socket | 
                                   (ON4KST)   |
                                   v          v
                              +------------------+
                              |  ON4KST Server   |
                              | (www.on4kst.info)|
                              +------------------+
```

### Components

1. **Connection Manager** (`On4kstConnectionManager`)
   - Manages TCP connection to `www.on4kst.info:23000` for each user
   - Handles login sequence (Login:, Password:, Your choice prompts)
   - Parses chat messages with pattern `/^([0-9]{4})Z (.*)>(.*)$/`
   - Maintains user list via `/sh us` command (parsing `/^\S{3,}\s{1,}\S+\s(.*)$/`)
   - Implements reconnection with exponential backoff
   - Provides callbacks for messages, connection status, and errors

2. **Notification Service** (`NotificationService`)
   - Orchestrates connections and notifications
   - Applies filtering logic: 'all' (always notify) or 'myCallsign' (notify only if message contains (USERNAME))
   - Manages connection lifecycle per user
   - Sends notifications via APNs service or Pushover service

3. **APNs Service** (`ApnsService`)
   - Wrapper around the `apn` library for sending notifications via Apple's service
   - Configured with APNs key, key ID, team ID, and bundle ID

4. **User Settings Service** (`UserSettingsService`)
   - In-memory storage for user credentials and settings
   - Can be replaced with database persistence for production

5. **User Service** (`UserService`)
   - Facade for accessing user settings

6. **Express API** (`userRoutes.ts`)
   - REST endpoints for settings synchronization
   - PUT `/api/v1/user/:username` - Save/update settings
   - GET `/api/v1/user/:username` - Retrieve settings (excluding password)
   - DELETE `/api/v1/user/:username` - Delete settings
   - GET `/api/v1/users` - List all users (excluding passwords)

## Setup

### Prerequisites

- Node.js >= 14.0.0
- npm >= 6.0.0
- For APNs support: Apple Developer account, APNs authentication key (.p8 file)
- For Pushover support: Pushover account (free tier available) and API token from Pushover.net

### Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd push-notifications-backend
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Set up environment variables (see Configuration section below)

4. Build the TypeScript code:
   ```bash
   npm run build
   ```

### Configuration

The application is configured via environment variables. Create a `.env` file in the root directory or set environment variables:

| Variable | Description | Required |
|----------|-------------|----------|
| `PORT` | HTTP server port (default: 3000) | No |
| `NODE_ENV` | Environment (`development` or `production`) | No |
| `APNS_KEY_PATH` | Path to APNs private key (.p8 file) | Yes (for APNs) |
| `APNS_KEY_ID` | APNs key ID | Yes (for APNs) |
| `APNS_TEAM_ID` | Apple Team ID | Yes (for APNs) |
| `APNS_BUNDLE_ID` | Bundle ID of the KstApp iOS app | Yes (for APNs) |
| `PUSHOVER_API_TOKEN` | Pushover application API token (provided by Pushover when you create an application) | Yes (for Pushover) |
| `ENCRYPTION_KEY` | For encrypting sensitive data at rest (if using persistent storage) | No |

Example `.env` file:
```
PORT=3000
NODE_ENV=development
APNS_KEY_PATH=./keys/auth_key.p8
APNS_KEY_ID=ABC123DEFG
APNS_TEAM_ID=ABCDE12345
APNS_BUNDLE_ID=com.example.kstapp
PUSHOVER_API_TOKEN=your_pushover_application_token_here
```

## Usage

### Development

```bash
# Start in development mode with auto-restart
npm run dev

# Or build and run
npm run build
npm start
```

### Production

```bash
# Build for production
npm run build

# Start the server
npm start
```

The service will start listening on the configured port (default 3000).

## API Endpoints

All API endpoints use JSON format and require HTTPS in production for security.

### Save or Update User Settings
```
PUT /api/v1/user/:username
```

**Parameters:**
- `username` (path parameter): ON4KST username (must match username in body)

**Request Body:**
```json
{
  "on4kstUsername": "string",      // ON4KST username (should match :username)
  "on4kstPassword": "string",      // ON4KST password
  "gridSquare": "string",          // Optional: Maidenhead grid square (e.g., "FN20rl")
  "notificationsEnabled": boolean, // Enable/disable notifications
  "notificationFilter": "all" | "myCallsign", // Notification filter
  "deviceToken": "string",         // Optional: APNs device token
  "pushoverUserKey": "string"      // Optional: Pushover user key (future feature)
}
```

**Response:**
```json
{
  "message": "Notifications enabled for user ON1ABC",
  "username": "ON1ABC"
}
```

### Get User Settings
```
GET /api/v1/user/:username
```

**Parameters:**
- `username` (path parameter): ON4KST username

**Response:**
```json
{
  "username": "ON1ABC",
  "gridSquare": "FN20rl",
  "notificationsEnabled": true,
  "notificationFlag": "myCallsign",
  "deviceToken": "abc123def456...",
  "createdAt": "2023-05-15T10:30:00.000Z",
  "updatedAt": "2023-05-15T10:30:00.000Z"
}
```
*Note: Password is never returned for security reasons.*

### Delete User Settings
```
DELETE /api/v1/user/:username
```

**Parameters:**
- `username` (path parameter): ON4KST username

**Response:**
```json
{
  "message": "User settings deleted for user ON1ABC"
}
```

### List All Users
```
GET /api/v1/users
```

**Response:**
```json
{
  "users": [
    {
      "username": "ON1ABC",
      "gridSquare": "FN20rl",
      "notificationsEnabled": true,
      "notificationFilter": "myCallsign",
      "deviceToken": "abc123def456...",
      "createdAt": "2023-05-15T10:30:00.000Z",
      "updatedAt": "2023-05-15T10:30:00.000Z"
    },
    // ... more users
  ],
  "count": 1
}
```
*Note: Passwords are never returned for security reasons.*

## Project Structure

```
push-notifications-backend/
├── src/
│   ├── models/
│   │   └── UserSettings.ts         # User settings interface
│   ├── services/
│   │   ├── ApnsService.ts          # APNs service wrapper
│   │   ├── PushoverService.ts      # Pushover service wrapper
│   │   ├── NotificationService.ts  # Main notification coordinator
│   │   ├── On4kstConnectionManager.ts # ON4KST connection manager
│   │   ├── UserSettingsService.ts  # Settings storage (in-memory)
│   │   └── UserService.ts          # Settings access facade
│   ├── routes/
│   │   └── userRoutes.ts           # Express API routes
│   ├── tests/
│   │   ├── ApnsService.test.ts
│   │   ├── NotificationService.test.ts
│   │   ├── On4kstConnectionManager.test.ts
│   │   ├── UserSettingsService.test.ts
│   │   └── UserService.test.ts
│   ├── index.ts                    # Express server entry point
│   └── tsconfig.json               # TypeScript configuration
├── .env                            # Environment variables (not in repo)
├── .gitignore
├── package.json
├── jest.config.js                  # Jest configuration
├── README.md                       # This file
└── DESIGN.md                       # Detailed design document
```

## Testing

Run the test suite:
```bash
# Run all tests
npm test

# Run tests in watch mode (development)
npm run test:watch
```

The test suite includes:
- Unit tests for each service
- Integration tests for the notification flow
- API route tests
- Connection manager tests

## Deployment

### Raspberry Pi Deployment

This service is designed to run efficiently on a Raspberry Pi:

1. Install Node.js on your Raspberry Pi:
   ```bash
   curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
   sudo apt-get install -y nodejs
   ```

2. Clone the repository and install dependencies as described above

3. Configure environment variables for APNs

4. Start the service:
   ```bash
   npm start
   ```

### Process Management

For production use, consider using a process manager like PM2:
```bash
npm install -g pm2
pm2 start npm -- start
```

### SSL/TLS

For production deployments, ensure the service is behind a reverse proxy (like Nginx) that handles SSL termination, or configure HTTPS directly in Node.js.

## Future Enhancements

### Phase 1 (Current Implementation)
- ✅ Backend service with APNs and Pushover support
- ✅ ON4KST connection management
- ✅ Message parsing and filtering
- ✅ Settings synchronization API
- ✅ Comprehensive test suite

### Phase 2 (Future)
- [ ] Database persistence (Redis, MongoDB, or PostgreSQL) for user settings
- [ ] Rate limiting on settings endpoint
- [ ] Enhanced logging and monitoring
- [ ] Health check endpoint
- [ ] Docker container support for easy deployment
- [ ] HTTPS support built into Node.js server
- [ ] Web interface for administration
- [ ] Analytics and metrics collection

### Phase 3 (iOS App Changes)
- [ ] Update KstApp iOS to synchronize with this backend
- [ ] Add backend URL configuration in app settings
- [ ] Implement "Sync with Backend" functionality
- [ ] Handle APNs device token registration and transmission

## Design Reference

For detailed architectural diagrams and design decisions, refer to [DESIGN.md](./DESIGN.md).

## Security Considerations

1. **Transport Security**: Always use HTTPS in production to protect credentials and settings
2. **Data Protection**: sensitive data (passwords, device tokens) should be encrypted at rest
3. **Access Control**: Consider adding authentication to the API in multi-tenant environments
4. **Rate Limiting**: Implement rate limiting on the settings endpoint to prevent abuse
5. **Input Validation**: All inputs are validated to prevent injection attacks

## Troubleshooting

### Common Issues

1. **APNs Not Working**
   - Verify APNs credentials are correct and files are accessible
   - Check that the bundle ID matches your iOS app
   - Ensure proper certificates/keys are generated in Apple Developer portal
   - Check logs for APNs initialization errors

2. **Connection Issues with ON4KST**
   - Verify network connectivity to `www.on4kst.info:23000`
   - Check credentials are correct
   - Ensure firewall allows outbound connections to port 23000
   - Look for connection error logs in stdout

3. **Authentication Failures**
   - Verify username/password are correct
   - Check that username in URL matches username in request body
   - Ensure credentials are properly encoded in requests

### Logging

The application outputs logs to stdout. In production, consider redirecting to a file or logging service:
```bash
npm start > logs/app.log 2>&1
```

## License

This project is licensed under the GPL v3 License - see the [LICENSE](../LICENSE) file for details.

## Acknowledgments

- Based on the original work by the [QLog team](https://github.com/foldynl/QLog/blob/master/service/kstchat/KSTChat.cpp)
- Inspired by the need for reliable push notifications in amateur radio applications
- Built with Node.js, TypeScript, and the Express framework