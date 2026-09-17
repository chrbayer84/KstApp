import On4kstConnectionManager from '../services/On4kstConnectionManager';

describe('On4kstConnectionManager', () => {

  describe('Regex Parsing', () => {
    // We can test the private regex methods by testing the public `isChatMessage` or by extracting the regex logic
    // For unit testing, since the methods are private, we'll cast to any to access the private methods for testing the regex
    let manager: any;

    beforeEach(() => {
      manager = new On4kstConnectionManager('testuser');
    });

    test('isChatMessage recognizes valid chat lines', () => {
      expect(manager.isChatMessage('1200Z ON1ABC>Hello')).toBe(true);
      expect(manager.isChatMessage('1205Z VA3IKE Ike>Test message')).toBe(true);
      expect(manager.isChatMessage('0001Z K8NWN>Message with > characters')).toBe(true);
      
      expect(manager.isChatMessage('Chat selection')).toBe(false);
      expect(manager.isChatMessage('Login:')).toBe(false);
    });

    test('handleChatMessage correctly parses time, sender, and message including name extraction and internal brackets', () => {
      // Mock the onMessageReceived callback
      const mockCallback = jest.fn();
      manager.onMessageReceived = mockCallback;

      // Regular message
      manager.handleChatMessage('1200Z ON1ABC>Hello');
      expect(mockCallback).toHaveBeenCalledWith({
        time: '1200',
        sender: 'ON1ABC',
        message: 'Hello'
      });
      mockCallback.mockClear();

      // Message with name in sender field
      manager.handleChatMessage('1205Z VA3IKE Ike>Test message');
      expect(mockCallback).toHaveBeenCalledWith({
        time: '1205',
        sender: 'VA3IKE', // The name "Ike" should be stripped
        message: 'Test message'
      });
      mockCallback.mockClear();

      // Message with > in body
      manager.handleChatMessage('0001Z K8NWN>Message with > characters > here');
      expect(mockCallback).toHaveBeenCalledWith({
        time: '0001',
        sender: 'K8NWN',
        message: 'Message with > characters > here'
      });
      mockCallback.mockClear();
      
      // Message with space after >
      manager.handleChatMessage('1210Z ON1ABC> Space leading message');
      expect(mockCallback).toHaveBeenCalledWith({
        time: '1210',
        sender: 'ON1ABC',
        message: 'Space leading message'
      });
      mockCallback.mockClear();
    });
  });
});
