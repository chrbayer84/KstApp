import request from 'supertest';
import app from '../index';

describe('Basic API Tests', () => {
  it('should return a welcome message', async () => {
    const response = await request(app).get('/');
    expect(response.status).toBe(200);
    expect(response.body.message).toBe('KstApp Push Notifications Backend is running!');
  });

  it('should return health check status', async () => {
    const response = await request(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('OK');
  });
});

describe('User Settings API', () => {
  const testUsername = 'TESTAPI';
  
  afterEach(async () => {
    // Clean up test data
    // Note: We would need to import UserService to clean up, but for now we'll skip
    // In a real test, we'd properly clean up
  });
  
  it('should create user settings', async () => {
    const response = await request(app)
      .put(`/api/v1/user/${testUsername}`)
      .send({
        on4kstUsername: testUsername,
        on4kstPassword: 'testpass123',
        gridSquare: 'FN20rl',
        notificationsEnabled: true,
        notificationFilter: 'myCallsign',
        deviceToken: 'devicetoken123'
      })
      .set('Accept', 'application/json');
    
    expect(response.status).toBe(200);
    expect(response.body.message).toContain(`Notifications enabled for user ${testUsername}`);
  });
  
  it('should get user settings', async () => {
    // First create a user
    await request(app)
      .put(`/api/v1/user/${testUsername}`)
      .send({
        on4kstUsername: testUsername,
        on4kstPassword: 'testpass123',
        notificationsEnabled: true,
        notificationFilter: 'all'
      });
    
    // Then get it
    const response = await request(app)
      .get(`/api/v1/user/${testUsername}`)
      .set('Accept', 'application/json');
    
    expect(response.status).toBe(200);
    expect(response.body.username).toBe(testUsername);
    expect(response.body.notificationsEnabled).toBe(true);
    expect(response.body.notificationFilter).toBe('all');
    // Password should not be returned
    expect(response.body.password).toBeUndefined();
  });
  
  it('should return 400 for invalid request', async () => {
    const response = await request(app)
      .put(`/api/v1/user/${testUsername}`)
      .send({
        // Missing password
        on4kstUsername: testUsername,
        notificationsEnabled: true
      });
    
    expect(response.status).toBe(400);
    expect(response.body.error).toBeDefined();
  });
  
  it('should return 404 for non-existent user', async () => {
    const response = await request(app)
      .get(`/api/v1/user/NONEXISTENTUSER`)
      .set('Accept', 'application/json');
    
    expect(response.status).toBe(404);
    expect(response.body.error).toBeDefined();
  });
  
  it('should delete user settings', async () => {
    // First create a user
    await request(app)
      .put(`/api/v1/user/${testUsername}`)
      .send({
        on4kstUsername: testUsername,
        on4kstPassword: 'testpass123',
        notificationsEnabled: true
      });
    
    // Then delete it
    const response = await request(app)
      .delete(`/api/v1/user/${testUsername}`)
      .set('Accept', 'application/json');
    
    expect(response.status).toBe(200);
    expect(response.body.message).toContain(`User settings deleted for user ${testUsername}`);
    
    // Verify it's gone
    const getResponse = await request(app)
      .get(`/api/v1/user/${testUsername}`)
      .set('Accept', 'application/json');
    
    expect(getResponse.status).toBe(404);
  });
});
