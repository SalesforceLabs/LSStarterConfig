# Queue System Setup Guide

This app now uses a queue-based architecture with worker dynos for handling deployments.

## Architecture

- **Web Dynos**: Handle HTTP requests, OAuth flow, and enqueue deployment jobs
- **Worker Dynos**: Process deployment jobs from the queue concurrently
- **Redis**: Stores the job queue and job state

## Setup Steps

### 1. Add Redis Add-on

```bash
heroku addons:create heroku-redis:mini -a <your-app-name>
```

This will automatically set the `REDIS_URL` environment variable.

### 2. Install Dependencies

The dependencies are already added to `package.json`:
- `bullmq` - Queue management
- `ioredis` - Redis client

Install them:
```bash
cd heroku-app
npm install
```

### 3. Deploy to Heroku

```bash
git add .
git commit -m "Add queue system with worker dynos"
git push heroku main
```

### 4. Scale Worker Dynos

After deployment, scale worker dynos:

```bash
# Scale to 10 Standard-1X worker dynos (for 50 concurrent deployments)
heroku ps:scale worker=10:standard-1x -a <your-app-name>
```

Or via Heroku Dashboard:
- Go to your app → **Resources** tab
- Find the `worker` process type
- Click the pencil icon
- Set quantity to `10` and size to `standard-1x`
- Click **Confirm**

### 5. Verify Setup

Check that both web and worker dynos are running:

```bash
heroku ps -a <your-app-name>
```

You should see:
- `web.1` and `web.2` (2 × Standard-2X)
- `worker.1` through `worker.10` (10 × Standard-1X)

## How It Works

1. **User clicks "Login & Deploy"**
   - Web dyno handles OAuth flow
   - After successful authentication, enqueues a deployment job
   - Returns job ID to user

2. **Worker dyno picks up job**
   - Worker processes job from queue
   - Runs deployment steps (login, verify sandbox, deploy configs)
   - Updates job progress with logs

3. **User polls for status**
   - Web dyno reads job status from Redis
   - Returns logs and status to user's browser

## Configuration

### Worker Concurrency

Each worker processes up to **5 jobs concurrently** (configured in `worker.js`):

```javascript
concurrency: 5, // Process up to 5 jobs concurrently per worker
```

With 10 workers × 5 concurrency = **50 concurrent deployments** capacity.

### Queue Settings

- **Completed jobs**: Keeps last 100 completed jobs
- **Failed jobs**: Keeps last 50 failed jobs
- Jobs are automatically cleaned up after these limits

## Monitoring

### Check Queue Status

```bash
# View dyno logs (includes worker logs)
heroku logs --tail -a <your-app-name>

# View only worker logs
heroku logs --tail --ps worker -a <your-app-name>
```

### Check Job Status via API

The `/status?id=<job-id>` endpoint returns:
- `status`: `pending`, `running`, `success`, or `error`
- `logs`: Array of log lines

## Troubleshooting

### Workers Not Processing Jobs

1. Check worker dynos are running:
   ```bash
   heroku ps -a <your-app-name>
   ```

2. Check worker logs:
   ```bash
   heroku logs --tail --ps worker -a <your-app-name>
   ```

3. Verify Redis is connected:
   ```bash
   heroku config:get REDIS_URL -a <your-app-name>
   ```

### Jobs Stuck in Queue

1. Check queue size in Redis (requires Redis CLI or dashboard)
2. Verify workers are running and not crashed
3. Check for errors in worker logs

### Scaling

To adjust capacity:
- **More concurrent jobs**: Increase worker concurrency in `worker.js`
- **More throughput**: Add more worker dynos
- **Less cost**: Reduce worker dynos or concurrency

## Cost Estimate

- **Web dynos**: 2 × Standard-2X ≈ $100/month
- **Worker dynos**: 10 × Standard-1X ≈ $250/month
- **Redis**: heroku-redis:mini ≈ $0-15/month (depends on usage)
- **Total**: ~$350-365/month
