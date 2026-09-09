# ImgFlow Provider Comparison
Based on my analysis of the ImgFlow providers and their background services, 
here's the comprehensive comparison table:
| Provider | HTTP API | CLI | Pictures | PDF | Other | # Formats | Image 
Processing Tech | Service Language | Performance (s) | Year Founded | GitHub 
Stars | Last Release | Date of Last GitHub Commit |
|----------|----------|-----|----------|-----|--------|------------|
---------------------|-----------------|------------------|--------------|
-------------|--------------|----------------------------|
| [Sharp](https://github.com/lovell/sharp) | ❌ | ✅ | ✅ | ❌ | ❌ | ~15 | libvips 
(via Node.js bindings) | JavaScript | 13.97 | 2013 | 32.0k | 2025-11-06 | 
2026-03-12 |
| [ImageMagick](https://github.com/ImageMagick/ImageMagick) | ❌ | ✅ | ✅ | ✅ | ✅ | 
200+ | ImageMagick C++, MagickCore | C++ | 30.62 | 1987 | 15.9k | 2025-12-XX | 
2026-03-13 |
| [LibVips](https://github.com/libvips/libvips) | ❌ | ✅ | ✅ | ❌ | ❌ | ~20 | 
libvips C library | C | 21.89 | 2011 | 11.2k | 2025-12-XX | 2026-03-13 |
| [Imgproxy](https://github.com/imgproxy/imgproxy) | ✅ | ❌ | ✅ | ❌ | ❌ | ~20 | 
libvips (compiled in) | Go | 31.27† | 2017 | 10.5k | 2025-12-XX | 2026-03-13 |
| [Weserv](https://github.com/weserv/images) | ✅ | ❌ | ✅ | ❌ | ❌ | ~20 | libvips 
(compiled in) | C++ | 30.19† | 2015 | 2.6k | 2025-12-XX | 2025-12-18 |
| [Flyimg](https://github.com/flyimg/flyimg) | ✅ | ❌ | ✅ | ❌ | ❌ | ~15 | 
ImageMagick (via PHP Imagick) | PHP | N/A† | 2016 | 1.2k | 2025-12-XX | 
2026-03-05 |
## Performance Notes
Performance data from enhanced benchmark (7 test images, 4 sizes, 4 formats):
**🏆 Performance Rankings:**
1. **Sharp**: ⚡ 13.97s - **FASTEST** - Node.js/libvips optimization
2. **LibVips**: 🐢 21.89s - Very fast CLI processing
3. **Weserv**: 🌐 30.19s - HTTP API with CLI fallback  
4. **ImageMagick**: 🐢 30.62s - CLI processing
5. **Imgproxy**: 🌐 31.27s - HTTP API with CLI fallback
**📊 Key Insights:**
- **Sharp** is the fastest provider (40% faster than LibVips)
- **CLI providers** (Sharp, LibVips, ImageMagick) are generally faster
- **HTTP APIs** add overhead due to network calls and fallback logic
- **Node.js optimization** makes Sharp ideal for web development workflows

ImgFlow supports local CLI providers and Docker-backed HTTP providers. The
first available provider in `imgflow.backend_priority` is selected.

| Provider | Type | Processing engine | Notes |
| --- | --- | --- | --- |
| [Sharp](https://github.com/lovell/sharp) | CLI | libvips via Node.js | Fast local processing and broad web-format support |
| [LibVips](https://github.com/libvips/libvips) | CLI | libvips | Memory-efficient native CLI processing |
| [ImageMagick](https://github.com/ImageMagick/ImageMagick) | CLI | MagickCore | Broad format support, including PDF when delegates are installed |
| [Imgproxy](https://github.com/imgproxy/imgproxy) | HTTP API | libvips | Docker service with URL-based transformations |
| [Weserv](https://github.com/weserv/images) | HTTP API | libvips | Docker service with URL-based transformations |
| [Flyimg](https://github.com/flyimg/flyimg) | HTTP API | ImageMagick via PHP | Docker service with URL-based transformations |

## Performance

Performance varies with the input image set, requested formats, provider
versions, and host environment. See the generated
[performance benchmark report](performance/README.Performance.md) for current
cold-build time, warm-build time, cache-hit rate, output size, and compression
results.

Run the benchmark with:

```bash
```

The report includes only providers available when the benchmark runs. See
[docker.md](docker.md) to start the HTTP providers before benchmarking all six.

## Configuration

See [installation.md](installation.md) for `backend_priority` and provider URL
configuration. See [docker.md](docker.md) for service images, ports, health
checks, and troubleshooting.
