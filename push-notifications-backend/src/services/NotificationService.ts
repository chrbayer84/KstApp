import On4kstConnectionManager from './On4kstConnectionManager';
import ApnsService from './ApnsService';
import PushoverService from './PushoverService';
import UserSettingsService from './UserSettingsService';
import { UserSettings } from '../models/UserSettings';
import { createLogger } from '../utils/logger';

const log = createLogger('kst:notifications');

/**
 * Main service that coordinates ON4KST connections and push notifications
 */
class NotificationService {
  private connections: Map<string, On4kstConnectionManager> = new Map();
  private apnsService: ApnsService | null = null;
  private pushoverService: PushoverService | null = null;
  private pushoverDeepLinkUrl: string | undefined;

  constructor() {
    // Initialize APNs service if credentials are available
    this.initializeApnsService();
    // Initialize Pushover service if credentials are available
    this.initializePushoverService();
    // Get Pushover deep link URL from environment
    this.pushoverDeepLinkUrl = process.env.PUSHOVER_DEEP_LINK_URL;
  }

  /**
   * Initialize the APNs service from environment variables
   */
  private initializeApnsService(): void {
    const keyPath = process.env.APNS_KEY_PATH;
    const keyId = process.env.APNS_KEY_ID;
    const teamId = process.env.APNS_TEAM_ID;
    const bundleId = process.env.APNS_BUNDLE_ID;

    if (keyPath && keyId && teamId && bundleId) {
      try {
        this.apnsService = new ApnsService(keyPath, keyId, teamId, bundleId);
        log.info('APNs service initialized');
      } catch (error) {
        log.error('Failed to initialize APNs service:', error);
      }
    } else {
      log.info('APNs credentials not fully configured - push notifications disabled');
    }
  }

  /**
   * Initialize the Pushover service from environment variables
   */
  private initializePushoverService(): void {
    const apiToken = process.env.PUSHOVER_API_TOKEN;

    if (apiToken) {
      try {
        this.pushoverService = new PushoverService(apiToken);
        log.info('Pushover service initialized');
      } catch (error) {
        log.error('Failed to initialize Pushover service:', error);
      }
    } else {
      log.info('Pushover API token not configured - push notifications via Pushover disabled');
    }
  }

  // ... rest of the class remains the same for now
  
  /**
   * Start handling notifications for a user
   */
  async startUserNotifications(settings: UserSettings): Promise<void> {
    log.info(`[NOTIFY] Starting notifications for ${settings.username} | filter=${settings.notificationFilter} | pref=${settings.notificationService || 'none'} | pushoverKey=${!settings.pushoverUserKey ? 'missing' : settings.pushoverUserKey.slice(-4)} | deviceToken=${!!settings.deviceToken}`);

    // Stop any existing connection for this user
    await this.stopUserNotifications(settings.username);

    // Only create connection if notifications are enabled
    if (!settings.notificationsEnabled) {
      log.debug(`[NOTIFY] Notifications disabled for ${settings.username}, no connection created.`);
      return;
    }

    // Create new connection manager
    const connection = new On4kstConnectionManager(settings.username);
    connection.setSettings(settings);

    // Set up callbacks
    connection.setOnMessageReceived((message) => {
      this.handleIncomingMessage(settings.username, message);
    });

    connection.setOnConnectionStatusChange((isConnected) => {
      log.info(`[${settings.username}] Connection status: ${isConnected ? 'Connected' : 'Disconnected'}`);
    });

    connection.setOnError((error) => {
      log.error(`[${settings.username}] Connection error:`, error);
      // Attempt to restart connection after error
      setTimeout(() => {
        this.startUserNotifications(settings).catch(console.error);
      }, 10000); // Try again after 10 seconds
    });

    // Store the connection
    this.connections.set(settings.username, connection);

    // Connect to ON4KST
    await connection.connect();
  }
  
  /**
   * Stop handling notifications for a user
   */
  async stopUserNotifications(username: string): Promise<void> {
    const connection = this.connections.get(username);
    if (connection) {
      try {
        await connection.disconnect();
      } catch (error) {
        log.error(`Error disconnecting ${username}:`, error);
      }
      this.connections.delete(username);
    }
  }
  
  /**
   * Handle an incoming message from ON4KST
   */
  private async handleIncomingMessage(username: string, message: any): Promise<void> {
    log.debug(`[NOTIFY] handleIncomingMessage for ${username} | sender=${message.sender} | msg=${JSON.stringify(message.message).substring(0, 100)}`);

    // Get user settings
    const settings = await UserSettingsService.getSettings(username);
    if (!settings) {
      log.warn(`[NOTIFY] No settings found for ${username} — skipping notification. Registered users: [${UserSettingsService.getAllUsernames().join(', ')}]`);
      return;
    }
    if (!settings.notificationsEnabled) {
      log.debug(`[NOTIFY] Notifications disabled for ${username} — skipping message.`);
      return; // Notifications disabled for this user
    }

    log.debug(`[NOTIFY] Settings for ${username}: filter=${settings.notificationFilter} | service=${settings.notificationService || 'none'} | pushoverKey=${settings.pushoverUserKey?.slice(-4) || 'N/A'} | deviceToken=${!!settings.deviceToken}`);

    // Apply notification filter
    let shouldNotify = false;

    if (settings.notificationFilter === 'all') {
      shouldNotify = true;
      log.debug(`[NOTIFY] Filter='all' → will notify for message from ${message.sender}.`);
    } else if (settings.notificationFilter === 'myCallsign') {
      // Check if message contains user's callsign in parentheses (case-insensitive)
      const pattern = new RegExp(`\\(${settings.username.toUpperCase()}\\)`, 'i');
      shouldNotify = pattern.test(message.message);
      log.debug(`[NOTIFY] Filter='myCallsign' looking for pattern "\\(${username.toUpperCase()}\\)" in "${message.message}": ${shouldNotify ? 'MATCH' : 'NO MATCH'}`);
    } else {
      log.warn(`[NOTIFY] Unknown filter "${settings.notificationFilter}" for ${username} — skipping notification.`);
    }

    if (!shouldNotify) {
      log.debug(`[NOTIFY] Filter rejected message from ${message.sender} — no push notification will be sent.`);
      return; // Message doesn't match filter
    }

    log.info(`[NOTIFY] Message from ${message.sender} matches filter for ${username} — sending push notification.`);
    // Send push notification
    await this.sendPushNotification(settings, message);
  }
  
  /**
   * Send a push notification to the user
   */
  private async sendPushNotification(settings: UserSettings, message: any): Promise<void> {
    log.debug(`[NOTIFY] sendPushNotification for ${settings.username} | userPref=${settings.notificationService || 'none'} | pushoverService=${this.pushoverService ? 'init' : 'NULL'} | apnsService=${this.apnsService ? 'init' : 'NULL'} | pushoverKey=${settings.pushoverUserKey?.slice(-4) || 'NULL'} | deviceToken=${!!settings.deviceToken}`);

    // Determine which push service to use based on user preference and availability
    let useApns = false;
    let usePushover = false;

    if (settings.notificationService === 'pushover') {
      // User prefers Pushover
      usePushover = !!(settings.pushoverUserKey && this.pushoverService);
      log.debug(`[NOTIFY] User prefers pushover. pushoverKey=${!!settings.pushoverUserKey} pushoverService=${!!this.pushoverService} → usePushover=${usePushover}`);
      if (!usePushover) {
        // Fall back to APNs if Pushover not available
        useApns = !!(settings.deviceToken && this.apnsService);
        log.debug(`[NOTIFY] Pushover not available, fallback to APNs: deviceToken=${!!settings.deviceToken} apnsService=${!!this.apnsService} → useApns=${useApns}`);
      }
    } else if (settings.notificationService === 'apns') {
      // User prefers APNs
      useApns = !!(settings.deviceToken && this.apnsService);
      log.debug(`[NOTIFY] User prefers APNs. deviceToken=${!!settings.deviceToken} apnsService=${!!this.apnsService} → useApns=${useApns}`);
      if (!useApns) {
        // Fall back to Pushover if APNs not available
        usePushover = !!(settings.pushoverUserKey && this.pushoverService);
        log.debug(`[NOTIFY] APNs not available, fallback to Pushover: pushoverKey=${!!settings.pushoverUserKey} pushoverService=${!!this.pushoverService} → usePushover=${usePushover}`);
      }
    } else {
      // No preference: try APNs first, then Pushover
      useApns = !!(settings.deviceToken && this.apnsService);
      log.debug(`[NOTIFY] No service preference. Try APNs: deviceToken=${!!settings.deviceToken} apnsService=${!!this.apnsService} → useApns=${useApns}`);
      if (!useApns) {
        usePushover = !!(settings.pushoverUserKey && this.pushoverService);
        log.debug(`[NOTIFY] APNs not available, try Pushover: pushoverKey=${!!settings.pushoverUserKey} pushoverService=${!!this.pushoverService} → usePushover=${usePushover}`);
      }
    }

    if (useApns) {
      log.debug(`[NOTIFY] Sending via APNs to ${settings.username}...`);
      // Use APNs
      try {
        const title = 'ON4KST Chat';
        const body = `${message.sender}: ${message.message}`;

        const success = await this.apnsService!.sendNotification(
          settings.deviceToken!,
          title,
          body
        );

        log.debug(`[NOTIFY] APNs send result: ${success ? 'SUCCESS' : 'FAILED'}`);
        if (!success) {
          log.warn(`Failed to send push notification via APNs to ${settings.username}`);
        }
      } catch (error) {
        log.error(`Error sending push notification via APNs to ${settings.username}:`, error);
      }
    } else if (usePushover) {
      log.debug(`[NOTIFY] Sending via Pushover to ${settings.username}...`);
      // Use Pushover
      try {
        const title = 'ON4KST Chat';
        const messageText = `${message.sender}: ${message.message}`;

        const success = await this.pushoverService!.sendNotification(
          settings.pushoverUserKey!,
          messageText,
          title,
          0, // priority
          this.pushoverDeepLinkUrl // url
        );

        log.debug(`[NOTIFY] Pushover send result: ${success ? 'SUCCESS' : 'FAILED'}`);
        if (!success) {
          log.warn(`Failed to send push notification via Pushover to ${settings.username}`);
        }
      } catch (error) {
        log.error(`Error sending push notification via Pushover to ${settings.username}:`, error);
      }
    } else {
      log.warn(`Cannot send push notification: No valid push service configured for ${settings.username}. ` +
        `APNs: ${this.apnsService ? 'configured' : 'not configured'}, Pushover: ${this.pushoverService ? 'configured' : 'not configured'}. ` +
        `User has deviceToken: ${!!settings.deviceToken}, pushoverUserKey: ${!!settings.pushoverUserKey}, preferred service: ${settings.notificationService || 'none'}`);
    }
  }
  
  /**
   * Get all active connections
   */
  getActiveConnections(): string[] {
    return Array.from(this.connections.keys());
  }

  /**
   * Get diagnostic state for all connections
   */
  getDebugState(username?: string): any {
    const result: any = {
      serverStats: {
        pushoverService: !!this.pushoverService,
        apnsService: !!this.apnsService,
        pushoverDeepLinkUrl: this.pushoverDeepLinkUrl,
        registeredUsers: UserSettingsService.getAllUsernames(),
      },
      connections: {}
    };

    if (username) {
      // Get state for a specific user
      const connection = this.connections.get(username.toUpperCase());
      const settings = UserSettingsService.getSettings(username);
      // UserSettingsService.getSettings is async, but it's synchronous in our in-memory implementation
      // We use a synchronous approach since the service is actually synchronous despite the async signature
      result.connections[username.toUpperCase()] = {
        hasActiveConnection: !!connection,
        connectionState: connection ? connection.getDebugState() : null,
      };
      // Fetch settings synchronously via the internal Map
      result.userSettings = settings ? (async () => {
        const s = await settings;
        if (s) {
          const { password, ...safe } = s;
          return safe;
        }
        return null;
      })() : null;
    } else {
      for (const [user, connection] of this.connections.entries()) {
        result.connections[user] = connection.getDebugState();
      }
    }

    return result;
  }

  /**
   * Send a test push notification directly via Pushover (no on4kst message needed)
   */
  async testPushoverNotification(username: string): Promise<{ success: boolean; detail: string }> {
    const settings = await UserSettingsService.getSettings(username.toUpperCase());
    if (!settings) {
      log.error(`[TEST] No settings found for ${username}`);
      return { success: false, detail: `No settings found for "${username}". Have you PUT /api/v1/user/${username} already?` };
    }

    if (!this.pushoverService) {
      log.error('[TEST] Pushover service is not initialized');
      return { success: false, detail: 'Pushover service is not initialized. Check PUSHOVER_API_TOKEN in .env.' };
    }

    if (!settings.pushoverUserKey) {
      log.error(`[TEST] ${username} has no pushoverUserKey`);
      return { success: false, detail: `No pushoverUserKey set for "${username}". Include "pushoverUserKey" in your PUT body.` };
    }

    log.info(`[TEST] Sending test Pushover notification to ${username} (userKey suffix ${settings.pushoverUserKey.slice(-4)})`);
    const result = await this.pushoverService.sendNotification(
      settings.pushoverUserKey,
      `Test notification from KstApp backend at ${new Date().toISOString()}. If you see this, Pushover integration works!`,
      'Test Notification',
      0
    );

    return { success: result, detail: result ? 'Notification sent successfully. Check your Pushover app.' : 'Pushover API returned an error. Check the server logs for details.' };
  }

  /**
   * Simulate an incoming ON4KST message for testing the filter and push pipeline
   */
  async simulateMessage(username: string, sender: string, messageText: string): Promise<{ notified: boolean; detail: string }> {
    const settings = await UserSettingsService.getSettings(username.toUpperCase());
    if (!settings) {
      log.error(`[SIM] No settings found for ${username}`);
      return { notified: false, detail: `No settings found for "${username}".` };
    }

    const fakeMessage = {
      time: new Date().toISOString().substring(11, 16).replace(':', '') + 'Z',
      sender: sender,
      message: messageText
    };

    log.info(`[SIM] Simulating message from ${sender}: "${messageText}" for ${username}`);

    // Directly call handleIncomingMessage to test the full pipeline
    try {
      // Make private methods accessible via (this as any) hack for testing
      (this as any).handleIncomingMessage(username, fakeMessage);
      return { notified: true, detail: `Message "${sender}: ${messageText}" was processed. Check logs for filter/service decisions. If nothing arrived on your phone, check the filter: "${settings.notificationFilter}" and that ${settings.notificationService || 'default (APNs first)'} is available.` };
    } catch (error: any) {
      return { notified: false, detail: `Error: ${error?.message || error}` };
    }
  }

  /**
   * Shutdown all services
   */
  shutdown(): void {
    // Disconnect all connections
    for (const [username, connection] of this.connections.entries()) {
      try {
        connection.disconnect();
      } catch (error) {
        log.error(`Error disconnecting ${username} during shutdown:`, error);
      }
    }
    this.connections.clear();
    
    // Shutdown APNs service
    if (this.apnsService) {
      this.apnsService.shutdown();
    }
  }
}

// Export a singleton instance
export default new NotificationService();
