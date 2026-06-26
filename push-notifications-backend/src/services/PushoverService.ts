import https from 'https';
import querystring from 'querystring';

/**
 * Service for sending push notifications via Pushover.net
 */
class PushoverService {
  private apiToken: string;
  private apiUrl = 'https://api.pushover.net/1/messages.json';

  constructor(apiToken: string) {
    this.apiToken = apiToken;
  }

  /**
   * Send a push notification via Pushover
   * @param userKey - The user's Pushover user key
   * @param message - The message to send
   * @param title - Optional title for the notification
   * @param priority - Optional priority (-2 to 2)
   * @param url - Optional URL to open when notification is tapped
   * @returns Promise resolving to true if successful, false otherwise
   */
  sendNotification(userKey: string, message: string, title?: string, priority: number = 0, url?: string): Promise<boolean> {
    return new Promise((resolve, reject) => {
      // Build the post data object
      const postData: any = {
        token: this.apiToken,
        user: userKey,
        message: message,
        title: title || '',
        priority: priority.toString()
      };

      // Add URL if provided
      if (url !== undefined && url !== null) {
        postData.url = url;
      }

      const queryString = querystring.stringify(postData);

      const options = {
        method: 'POST',
        hostname: 'api.pushover.net',
        path: '/1/messages.json',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(queryString)
        }
      };

      const req = https.request(options, (res) => {
        let data = '';
        res.on('data', (chunk) => {
          data += chunk;
        });
        res.on('end', () => {
          try {
            const response = JSON.parse(data);
            if (res.statusCode === 200 && response.status === 1) {
              resolve(true);
            } else {
              console.error(`Pushover API error:`, response);
              resolve(false);
            }
          } catch (e) {
            console.error('Failed to parse Pushover response:', e);
            resolve(false);
          }
        });
      });

      req.on('error', (error) => {
        console.error('Error sending Pushover notification:', error);
        reject(false);
      });

      req.write(queryString);
      req.end();
    });
  }
}

export default PushoverService;