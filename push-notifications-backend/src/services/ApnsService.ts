import apn, { Provider, Notification } from 'apn';
import { createLogger } from '../utils/logger';

const log = createLogger('kst:apns');

/**
 * Service for sending push notifications via Apple Push Notification Service (APNs)
 */
class ApnsService {
  private provider: Provider | null = null;
  private readonly bundleId: string;
  
  constructor(private readonly apnsKeyPath: string, 
              private readonly apnsKeyId: string, 
              private readonly apnsTeamId: string,
              bundleId: string) {
    this.bundleId = bundleId;
    this.initializeProvider();
  }
  
  /**
   * Initialize the APNs provider
   */
  private initializeProvider(): void {
    try {
      this.provider = new Provider({
        token: {
          key: this.apnsKeyPath, // Path to the .p8 key file
          keyId: this.apnsKeyId,
          teamId: this.apnsTeamId
        },
        production: false // Set to true for production
      });
      
      log.info('APNs provider initialized');
    } catch (error) {
      log.error('Failed to initialize APNs provider:', error);
      this.provider = null;
    }
  }
  
  /**
   * Send a push notification to a device
   */
  async sendNotification(deviceToken: string, title: string, body: string): Promise<boolean> {
    if (!this.provider) {
      log.error('APNs provider not initialized');
      return false;
    }
    
    if (!deviceToken) {
      log.error('No device token provided');
      return false;
    }
    
    try {
      const notification = new Notification();
      notification.topic = this.bundleId;
      notification.alert = {
        title: title,
        body: body
      };
      notification.sound = 'default';
      notification.badge = 1;
      
      // Send the notification
      const result = await this.provider.send(notification, deviceToken);
      
      // Check if the notification was sent successfully
      if (result.sent.length > 0) {
        log.info(`Notification sent successfully to device: ${deviceToken.substring(0, 10)}...`);
        return true;
      } else {
        log.warn('Failed to send notification:', result.failed);
        return false;
      }
    } catch (error) {
      log.error('Error sending APNs notification:', error);
      return false;
    }
  }
  
  /**
   * Shutdown the provider (call when application is terminating)
   */
  shutdown(): void {
    if (this.provider) {
      this.provider.shutdown();
      log.info('APNs provider shutdown');
    }
  }
}

export default ApnsService;
