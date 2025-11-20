const express = require('express');
const redis = require('redis');
const { v4: uuidv4 } = require('uuid');

const app = express();
const PORT = process.env.PORT || 3000;
const INSTANCE_ID = process.env.INSTANCE_ID || 'unknown';
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';

// Initialize Redis client
let redisClient;

async function initRedis() {
  try {
    redisClient = redis.createClient({ url: REDIS_URL });
    await redisClient.connect();
    console.log('Connected to Redis');
  } catch (error) {
    console.error('Redis connection error:', error);
    redisClient = null;
  }
}

// Middleware
app.use(express.json());
app.use(express.static('public'));

// Store session ID for tracking requests
const sessionId = uuidv4();
let requestCount = 0;

// Health check endpoint for Traefik
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    instance: INSTANCE_ID,
    timestamp: new Date().toISOString()
  });
});

// Main route
app.get('/', async (req, res) => {
  requestCount++;
  
  const responseData = {
    message: `Hello from Web App Instance ${INSTANCE_ID}!`,
    instanceId: INSTANCE_ID,
    sessionId: sessionId,
    requestNumber: requestCount,
    timestamp: new Date().toISOString(),
    hostname: req.hostname,
    userAgent: req.get('User-Agent')
  };

  // Try to store visit count in Redis
  if (redisClient) {
    try {
      const totalVisits = await redisClient.incr('total_visits');
      const instanceVisits = await redisClient.incr(`instance_${INSTANCE_ID}_visits`);
      
      responseData.stats = {
        totalVisits: totalVisits,
        instanceVisits: instanceVisits
      };
    } catch (error) {
      console.error('Redis operation error:', error);
      responseData.redisError = 'Could not access Redis';
    }
  }

  res.json(responseData);
});

// API endpoint to get statistics
app.get('/api/stats', async (req, res) => {
  const stats = {
    instanceId: INSTANCE_ID,
    sessionId: sessionId,
    localRequests: requestCount,
    timestamp: new Date().toISOString()
  };

  if (redisClient) {
    try {
      const totalVisits = await redisClient.get('total_visits') || 0;
      const instance1Visits = await redisClient.get('instance_1_visits') || 0;
      const instance2Visits = await redisClient.get('instance_2_visits') || 0;
      
      stats.global = {
        totalVisits: parseInt(totalVisits),
        instance1Visits: parseInt(instance1Visits),
        instance2Visits: parseInt(instance2Visits)
      };
    } catch (error) {
      stats.redisError = 'Could not fetch Redis stats';
    }
  }

  res.json(stats);
});

// Load testing endpoint
app.get('/api/load-test', (req, res) => {
  const startTime = Date.now();
  
  // Simulate some work
  let sum = 0;
  for (let i = 0; i < 1000000; i++) {
    sum += Math.random();
  }
  
  const endTime = Date.now();
  
  res.json({
    instanceId: INSTANCE_ID,
    processingTime: endTime - startTime,
    result: sum,
    timestamp: new Date().toISOString()
  });
});

// Reset stats endpoint
app.post('/api/reset', async (req, res) => {
  requestCount = 0;
  
  if (redisClient) {
    try {
      await redisClient.del('total_visits');
      await redisClient.del('instance_1_visits');
      await redisClient.del('instance_2_visits');
      res.json({ message: 'Stats reset successfully', instanceId: INSTANCE_ID });
    } catch (error) {
      res.status(500).json({ error: 'Could not reset Redis stats' });
    }
  } else {
    res.json({ message: 'Local stats reset', instanceId: INSTANCE_ID });
  }
});

// Error handling
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ 
    error: 'Something went wrong!', 
    instanceId: INSTANCE_ID 
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ 
    error: 'Route not found', 
    instanceId: INSTANCE_ID,
    requestedPath: req.path
  });
});

// Start server
async function startServer() {
  await initRedis();
  
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Web App Instance ${INSTANCE_ID} running on port ${PORT}`);
    console.log(`📊 Session ID: ${sessionId}`);
    console.log(`🔗 Redis URL: ${REDIS_URL}`);
    console.log(`⏰ Started at: ${new Date().toISOString()}`);
  });
}

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('Received SIGTERM, shutting down gracefully...');
  if (redisClient) {
    await redisClient.quit();
  }
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('Received SIGINT, shutting down gracefully...');
  if (redisClient) {
    await redisClient.quit();
  }
  process.exit(0);
});

startServer().catch(error => {
  console.error('Failed to start server:', error);
  process.exit(1);
});