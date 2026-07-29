# Docker Services for ImgFlow

ImgFlow provides Docker services for image optimization. These services can be used during development to dynamically compress images while building your Jekyll site.

## Quick Start

```bash
# Start all services
docker-compose -f docker-compose.test.yml --env-file .env.test up -d

# Check status
./check-test-services.sh

# Stop services
docker-compose -f docker-compose.test.yml down
```

## Services

### HTTP API Services (Work with ImgFlow)

| Service | Port | Image | API Type | Use Case |
|---------|------|-------|----------|----------|
| **Imgproxy** | 33001 | `darthsim/imgproxy:latest` | HTTP API | Fast, reliable |
| **Weserv** | 33007 | `ghcr.io/weserv/images:5.x` | HTTP API | Battle-tested |
| **Flyimg** | 33008 | `flyimg/flyimg:latest` | HTTP API | On-the-fly |

### Manual-Only Services (Web UI - No Programmatic Access)

# All services now support programmatic access

### Provider Type Summary

#### **HTTP API Services** (Recommended for ImgFlow)

- **Imgproxy**, **Weserv**, **Flyimg**
- Automatically work with ImgFlow
- Use Docker services
- Best for performance and scalability

#### **CLI Tools** (Local Installation)

- **ImageMagick**, **LibVips**, **Sharp**
- Install locally with package managers
- Work automatically with ImgFlow
- No Docker required

# All providers now support programmatic access

## Configuration

### Environment Variables

Copy `.env.example` to `.env.test`:

```bash
cp .env.example .env.test
```

Default ports in `.env.test`:

```bash
IMGPROXY_PORT=33001
WESERV_PORT=33007
FLYIMG_PORT=33008
```

### Jekyll Configuration

Add to `_config.yml`:

```yaml
imgflow:
  backend_priority:
    - imgproxy
    - weserv
    - flyimg
    - imagemagick
    - libvips
    - sharp
  
  # HTTP API URLs
  imgproxy_url: "http://localhost:33001"
  weserv_url: "http://localhost:33007"
  flyimg_url: "http://localhost:33008"
```

## Usage

### Development Workflow

1. **Start Docker services:**

   ```bash
   docker-compose -f docker-compose.test.yml up -d
   ```

2. **Run Jekyll:**

   ```bash
   jekyll serve
   ```

3. **Add images to `assets/images/originals/`**
   - ImgFlow automatically optimizes them
   - Uses Docker services for processing
   - Saves to `assets/images/optimized/`

### Testing Services

```bash
# Test Imgproxy
curl "http://localhost:33001/health"

# Test Weserv
curl "http://localhost:33007/?url=https://picsum.photos/800/600&w=400&output=webp&q=80"

# Test Flyimg
curl "http://localhost:33008/upload/w_400,q_80,o_webp/https://picsum.photos/800/600"
```

# All services now provide HTTP API access

## Service Details

### Imgproxy

- **Port:** 33001
- **API:** `/health` endpoint
- **Usage:** Fast image resizing and format conversion
- **Best for:** Performance-critical applications

### Weserv

- **Port:** 33007
- **API:** Query parameters (`?url=...&w=...&output=...&q=...`)
- **Usage:** Battle-tested image processing
- **Best for:** Reliability and stability

### Flyimg

- **Port:** 33008
- **API:** Path-based (`/upload/w_300,q_80,o_webp/...`)
- **Usage:** On-the-fly image processing
- **Best for:** Dynamic resizing needs

## Health Check Script

Use the provided health check script:

```bash
./check-test-services.sh
```

This script:

- ✅ Checks all HTTP API services
- ⚠️ Warns about manual-only services
- ❌ Reports missing local CLI tools
- 📋 Provides installation instructions

## Troubleshooting

### Services Not Starting

```bash
# Check Docker is running
docker --version

# Check for port conflicts
lsof -i :33001,33007,33008

# View logs
docker-compose -f docker-compose.test.yml logs
```

### Service Not Responding

```bash
# Restart specific service
docker-compose -f docker-compose.test.yml restart imgproxy

# Check container status
docker-compose -f docker-compose.test.yml ps

# View service logs
docker-compose -f docker-compose.test.yml logs imgproxy
```

### Image Processing Issues

1. **Check service health:**

   ```bash
   ./check-test-services.sh
   ```

2. **Verify configuration:**
   - Service URLs match ports
   - Provider priority is correct

3. **Check Jekyll logs:**
   - Look for provider error messages
   - Verify `backend_priority` configuration

## Production Considerations

### For Development

- Use Docker services for convenience
- Automatic image processing
- Easy to start/stop

### For Production

- Consider using remote services
- Commit optimized images to repository
- Use CI/CD for image processing

### Performance Tips

- Use `imgproxy` or `weserv` for best performance
- Limit size variants to what you need
- Set appropriate quality (85 is good balance)

## File Structure

```
docker-compose.base.yml     # Service definitions
docker-compose.test.yml     # Test configuration with ports
.env.example               # Environment variables template
.env.test                  # Test environment variables
check-test-services.sh     # Health check script
```

## Security Notes

- Services run on non-standard ports (33001, 33007, 33008)
- Only expose services to localhost in development
- Use proper authentication in production
- Keep Docker images updated

## License

Each Docker service has its own license. Check the respective repositories for details.
