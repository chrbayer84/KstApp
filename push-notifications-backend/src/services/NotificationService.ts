import On4kstConnectionManager from './On4kstConnectionManager';
import ApnsService from './ApnsService';
import PushoverService from './PushoverService';
import UserSettingsService from './UserSettingsService';
import { UserSettings } from '../models/UserSettings';

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
        console.log('APNs service initialized');
      } catch (error) {
        console.error('Failed to initialize APNs service:', error);
      }
    } else {
      console.log('APNs credentials not fully configured - push notifications disabled');
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
        console.log('Pushover service initialized');
      } catch (error) {
        console.error('Failed to initialize Pushover service:', error);
      }
    } else {
      console.log('Pushover API token not configured - push notifications via Pushover disabled');
    }
  }

  // ... rest of the class remains the same for now
  
  /**
   * Start handling notifications for a user
   */
  async startUserNotifications(settings: UserSettings): Promise<void> {
    // Stop any existing connection for this user
    await this.stopUserNotifications(settings.username);

    // Only create connection if notifications are enabled
    if (!settings.notificationsEnabled) {
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
      console.log(`[${settings.username}] Connection status: ${isConnected ? 'Connected' : 'Disconnected'}`);
    });

    connection.setOnError((error) => {
      console.error(`[${settings.username}] Connection error:`, error);
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
        console.error(`Error disconnecting ${username}:`, error);
      }
      this.connections.delete(username);
    }
  }
  
  /**
   * Handle an incoming message from ON4KST
   */
  private async handleIncomingMessage(username: string, message: any): Promise<void> {
    // Get user settings
    const settings = await UserSettingsService.getSettings(username);
    if (!settings || !settings.notificationsEnabled) {
      return; // Notifications disabled for this user
    }
    
    // Apply notification filter
    let shouldNotify = false;
    
    if (settings.notificationFilter === 'all') {
      shouldNotify = true;
    } else if (settings.notificationFilter === 'myCallsign') {
      // Check if message contains user's callsign in parentheses (case-insensitive)
      const pattern = new RegExp(`\\(${settings.username.toUpperCase()}\\)`, 'i');
      shouldNotify = pattern.test(message.message);
    }
    
    if (!shouldNotify) {
      return; // Message doesn't match filter
    }
    
    // Send push notification
    await this.sendPushNotification(settings, message);
  }
  
  /**
   * Send a push notification to the user
   */
  private async sendPushNotification(settings: UserSettings, message: any): Promise<void> {
    // Determine which push service to use based on user preference and availability
    let useApns = false;
    let usePushover = false;

    if (settings.notificationService === 'pushover') {
      // User prefers Pushover
      usePushover = !!(settings.pushoverUserKey && this.pushoverService);
      if (!usePushover) {
        // Fall back to APNs if Pushover not available
        useApns = !!(settings.deviceToken && this.apnsService);
      }
    } else if (settings.notificationService === 'apns') {
      // User prefers APNs
      useApns = !!(settings.deviceToken && this.apnsService);
      if (!useApns) {
        // Fall back to Pushover if APNs not available
        usePushover = !!(settings.pushoverUserKey && this.pushoverService);
      }
    } else {
      // No preference: try APNs first, then Pushover
      useApns = !!(settings.deviceToken && this.apnsService);
      if (!useApns) {
        usePushover = !!(settings.pushoverUserKey && this.pushoverService);
      }
    }

    if (useApns) {
      // Use APNs
      try {
        const title = 'ON4KST Chat';
        const body = `${message.sender}: ${message.message}`;

        const success = await this.apnsService!.sendNotification(
          settings.deviceToken!,
          title,
          body
        );

        if (!success) {
          console.warn(`Failed to send push notification via APNs to ${settings.username}`);
        }
      } catch (error) {
        console.error(`Error sending push notification via APNs to ${settings.username}:`, error);
      }
    } else if (usePushover) {
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

        if (!success) {
          console.warn(`Failed to send push notification via Pushover to ${settings.username}`);
        }
      } catch (error) {
        console.error(`Error sending push notification via Pushover to ${settings.username}:`, error);
      }
    } else {
      console.warn(`Cannot send push notification: No valid push service configured for ${settings.username}. ` +
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
   * Shutdown all services
   */
  shutdown(): void {
    // Disconnect all connections
    for (const [username, connection] of this.connections.entries()) {
      try {
        connection.disconnect();
      } catch (error) {
        console.error(`Error disconnecting ${username} during shutdown:`, error);
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
