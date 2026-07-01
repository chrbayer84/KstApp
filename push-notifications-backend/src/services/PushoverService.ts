import https from 'https';
import querystring from 'querystring';
import { createLogger } from '../utils/logger';

const log = createLogger('kst:pushover');

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
      log.debug(`[PUSHOVER] Preparing notification for userKey suffix ${userKey?.slice(-4) || '???'} | message: "${message.substring(0, 50)}..."`);

      // Validate inputs
      if (!this.apiToken || this.apiToken === 'your_pushover_application_token_here') {
        log.error('[PUSHOVER] API token is missing or is still the placeholder value.');
        resolve(false);
        return;
      }
      if (!userKey || userKey.length < 30) {
        log.error(`[PUSHOVER] Invalid userKey provided (length ${userKey?.length || 0}). A valid Pushover user key is 30 characters.`);
        resolve(false);
        return;
      }

      const postData: Record<string, string> = {
        token: this.apiToken,
        user: userKey,
        message: message,
        priority: priority.toString()
      };

      // Only add title if it's a real, non-empty string — Pushover falls back to app name when omitted
      if (title && title.trim().length > 0) {
        postData.title = title;
      }

      // Add URL if provided
      if (url !== undefined && url !== null && url.trim().length > 0) {
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

      log.debug(`[PUSHOVER] POST body length: ${Buffer.byteLength(queryString)} bytes | fields: ${Object.keys(postData).join(', ')}`);

      const req = https.request(options, (res) => {
        let data = '';
        res.on('data', (chunk) => {
          data += chunk;
        });
        res.on('end', () => {
          log.debug(`[PUSHOVER] HTTP ${res.statusCode} | raw response: ${data.trim()}`);
          try {
            const response = JSON.parse(data);
            if (res.statusCode === 200 && response.status === 1) {
              log.debug(`[PUSHOVER] Notification sent successfully (request ${response.request})`);
              resolve(true);
            } else {
              log.error(`[PUSHOVER] API returned non-success. HTTP ${res.statusCode} body: ${JSON.stringify(response)}`);
              resolve(false);
            }
          } catch (e: any) {
            log.error(`[PUSHOVER] Failed to parse response body. HTTP ${res.statusCode} raw: "${data}"`, e?.message || e);
            resolve(false);
          }
        });
      });

      req.on('error', (error) => {
        log.error(`Error sending Pushover notification: ${error.message}`);
        reject(false);
      });

      req.write(queryString);
      req.end();
    });
  }
}

export default PushoverService;