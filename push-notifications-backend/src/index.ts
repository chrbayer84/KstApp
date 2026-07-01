import 'dotenv/config';
import express, { Request, Response, NextFunction } from 'express';
import userRoutes from './routes/userRoutes';
import NotificationService from './services/NotificationService';
import { createLogger } from './utils/logger';

const log = createLogger('kst:app');

// Create Express app
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());

// Request logging middleware
app.use((req: Request, res: Response, next: NextFunction) => {
  log.info(`${new Date().toISOString()} - ${req.method} ${req.path}`);
  next();
});

// Health check endpoint
app.get('/health', (req: Request, res: Response) => {
  res.json({ 
    status: 'OK', 
    timestamp: new Date().toISOString(),
    activeConnections: NotificationService.getActiveConnections().length
  });
});

// API routes
app.use('/api/v1/user', userRoutes);

// Root endpoint
app.get('/', (req: Request, res: Response) => {
  res.json({ 
    message: 'KstApp Push Notifications Backend is running!',
    version: '1.0.0',
    endpoints: {
      health: '/health',
      userSettings: '/api/v1/user/:username',
      users: '/api/v1/user'
    }
  });
});

// 404 handler
app.use((req: Request, res: Response) => {
  res.status(404).json({ 
    error: 'Not Found',
    path: req.originalUrl
  });
});

// Error handling middleware
app.use((error: any, req: Request, res: Response, next: NextFunction) => {
  log.error('Error:', error);
  res.status(500).json({ 
    error: 'Internal Server Error',
    message: process.env.NODE_ENV === 'development' ? error.message : undefined
  });
});

// Graceful shutdown
const shutdown = async () => {
  log.info('Shutting down server...');
  NotificationService.shutdown();
  process.exit(0);
};

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

// Start server
const server = app.listen(PORT, () => {
  log.info(`Server is running on port ${PORT}`);
  log.info(`Environment: ${process.env.NODE_ENV || 'development'}`);
});

export default app;
