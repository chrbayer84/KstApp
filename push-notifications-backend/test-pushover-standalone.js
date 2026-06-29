const https = require('https');
const querystring = require('querystring');

// Configuration
const PUSHOVER_API_TOKEN = process.env.PUSHOVER_API_TOKEN;
const PUSHOVER_USER_KEY = process.argv[2]; // Pass user key as first argument

if (!PUSHOVER_API_TOKEN) {
  console.error('Error: PUSHOVER_API_TOKEN environment variable not set');
  console.error('Usage: PUSHOVER_API_TOKEN=your_token node test-pushover.js <user_key>');
  process.exit(1);
}

if (!PUSHOVER_USER_KEY) {
  console.error('Error: Pushover user key required as first argument');
  console.error('Usage: node test-pushover.js <user_key>');
  process.exit(1);
}

// Build request
const postData = {
  token: PUSHOVER_API_TOKEN,
  user: PUSHOVER_USER_KEY,
  title: 'KstApp Test Message',
  message: `This is a test from the KstApp backend at ${new Date().toISOString()}`,
  priority: '0',
  url: 'kstapp://chat',
  url_title: 'Open KstApp'
};

const queryStr = querystring.stringify(postData);

const options = {
  method: 'POST',
  hostname: 'api.pushover.net',
  path: '/1/messages.json',
  headers: {
    'Content-Type': 'application/x-www-form-urlencoded',
    'Content-Length': Buffer.byteLength(queryStr)
  }
};

console.log('Sending test notification...');
console.log('Token:', PUSHOVER_API_TOKEN.substring(0, 8) + '...');
console.log('User Key:', PUSHOVER_USER_KEY.substring(0, 8) + '...');

const req = https.request(options, (res) => {
  let data = '';
  res.on('data', (chunk) => { data += chunk; });
  res.on('end', () => {
    try {
      const response = JSON.parse(data);
      console.log('\nPushover API Response:');
      console.log(JSON.stringify(response, null, 2));

      if (res.statusCode === 200 && response.status === 1) {
        console.log('\n✅ Test notification sent successfully!');
        console.log('Remaining requests:', response.request);
        console.log('Check your device for the notification.');
      } else {
        console.error('\n❌ Failed to send notification');
        console.error('Status Code:', res.statusCode);
        console.error('Response:', response);
        process.exit(1);
      }
    } catch (e) {
      console.error('Failed to parse response:', data);
      process.exit(1);
    }
  });
});

req.on('error', (error) => {
  console.error('Request error:', error);
  process.exit(1);
});

req.write(queryStr);
req.end();
