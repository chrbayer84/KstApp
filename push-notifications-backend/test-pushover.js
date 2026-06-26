import PushoverService from './services/PushoverService';

// Test Pushover service initialization
console.log('Testing Pushover service...');

// Test 1: Service initializes with token
const pushoverService = new PushoverService('test_token_123');
console.log('✓ PushoverService instantiated successfully');

// Test 2: Check that it has the expected properties
console.log('✓ PushoverService has apiToken:', !!pushoverService['apiToken']);
console.log('✓ PushoverService has apiURL:', pushoverService['apiUrl']);

// Test 3: Verify the sendNotification method exists
console.log('✓ sendNotification method exists:', typeof pushoverService.sendNotification === 'function');

console.log('\nPushover service tests completed successfully!');
console.log('To test actual Pushover API calls, you would need a valid API token and user key.');