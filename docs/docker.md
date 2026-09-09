# Docker Services for ImgFlow

ImgFlow provides Docker services for image optimization. These services can be used during development to dynamically compress images while building your Jekyll site.

## Quick Start

```bash
# Start all services (pulls missing images, recreates stale containers)
rake start_services

# Check status
rake check_services

# Check if pinned images are outdated
rake check_docker_images

# Stop services
rake stop_services
```

## Services

### HTTP API Services (Work with ImgFlow)

| Service | Port | Image | API Type | Use Case |
| --- | ---: | --- | --- | --- |
| **Imgproxy** | 4022 | `ghcr.io/imgproxy/imgproxy:v4.0.14` | HTTP API | Fast, reliable |
| **Weserv** | 4026 | `ghcr.io/weserv/images:5.x` | HTTP API | Battle-tested |
| **Flyimg** | 4030 | `flyimg/flyimg:1.12.5` | HTTP API | On-the-fly |

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
IMGPROXY_PORT=4022
WESERV_PORT=4026
FLYIMG_PORT=4030
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
  imgproxy_url: "http://localhost:4022"
  weserv_url: "http://localhost:4026"
  flyimg_url: "http://localhost:4030"
```

## Usage

### Development Workflow

1. **Start Docker services:**

   ```bash
   rake start_services
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
curl "http://localhost:4022/health"

# Test Weserv
curl "http://localhost:4026/?url=https://picsum.photos/800/600&w=400&output=webp&q=80"

# Test Flyimg
curl "http://localhost:4030/upload/w_400,q_80,o_webp/https://picsum.photos/800/600"
```

# All services now provide HTTP API access

## Service Details

### Imgproxy

- **Port:** 4022
- **API:** `/health` endpoint
- **Usage:** Fast image resizing and format conversion
- **Best for:** Performance-critical applications

### Weserv

- **Port:** 4026
- **API:** Query parameters (`?url=...&w=...&output=...&q=...`)
- **Usage:** Battle-tested image processing
- **Best for:** Reliability and stability
- **Note:** The test container sets `shm_size: 512mb` because Weserv's nginx
  proxy_cache uses `/dev/shm` (default 64MB is too small for bulk processing).
  The startup command is idempotent — it removes any existing
  `weserv_limit_input_pixels` directive before inserting one, so restarts
  do not accumulate duplicates.

### Flyimg

- **Port:** 4030
- **API:** Path-based (`/upload/w_300,q_80,o_webp/...`)
- **Usage:** On-the-fly image processing
- **Best for:** Dynamic resizing needs

## Health Check

Use the provided rake task:

```bash
rake check_services
```

This task:

- ✅ Checks all HTTP API services (Imgproxy, Weserv, Flyimg)
- ✅ Checks local CLI tools (ImageMagick, LibVips, Sharp)
- ❌ Reports services that are not responding
- 📋 Suggests `rake start_services` to fix issues

To check if pinned Docker images are outdated:

```bash
rake check_docker_images              # report only
STRICT=true rake check_docker_images  # exit 1 if any pin is outdated
```

## Troubleshooting

### Services Not Starting

```bash
# Check Docker is running
docker --version

# Check for port conflicts
lsof -i :4022,4026,4030

# View logs
docker-compose -f docker-compose.test.yml logs
```

### Service Not Responding

```bash
# Restart all services
rake stop_services
rake start_services

# Check container status
docker-compose -f docker-compose.test.yml ps

# View service logs
docker-compose -f docker-compose.test.yml logs imgproxy
```

### Image Processing Issues

1. **Check service health:**

   ```bash
   rake check_services
   ```

2. **Verify configuration:**
   - Service URLs match ports
   - Provider priority is correct

3. **Check Jekyll logs:**
   - Look for provider error messages
   - Verify `backend_priority` configuration

### Weserv Empty Responses / EOFError

Weserv's nginx proxy_cache stores up to 250MB in `/dev/shm`. The Docker
default 64MB `/dev/shm` can fill during bulk image processing, causing
`No space left on device` errors that return empty HTTP responses. The
test compose file sets `shm_size: 512mb` to avoid this. If you see
`EOFError: end of file reached` from the Weserv provider, check:

```bash
docker exec imgflow-weserv-test df -h /dev/shm
docker logs imgflow-weserv-test 2>&1 | grep "No space"
```

### Weserv nginx Directive Duplication

The test container's startup command injects `weserv_limit_input_pixels`
into the nginx config. The command is idempotent (deletes any existing
directive before inserting), but if you see
`nginx: [emerg] "weserv_limit_input_pixels" directive is duplicate`,
remove the stale container and recreate it:

```bash
docker rm -f imgflow-weserv-test
rake start_services
```

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
docker-compose.base.yml     # Base service definitions (shared image pins)
docker-compose.yml          # Production override
docker-compose.test.yml     # Test configuration with ports
.env.example               # Environment variables template
.env.test                  # Test environment variables
```

## Security Notes

- Services run on non-standard ports (4022, 4026, 4030)
- Only expose services to localhost in development
- Use proper authentication in production
- Keep Docker images updated

## License

Each Docker service has its own license. Check the respective repositories for details.
