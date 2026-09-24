# Enhanced ImgFlow Performance Benchmark Report (DEFAULT SET)

**Generated:** 2026-09-11T12:59:16+0200
**Ruby Version:** 3.4.10
**Operating System:** macOS 26.6.2
**CPU:** Apple M2
**Memory:** 24.0 GB
**CPU Cores:** 8 total, 7 used for testing
**Test Set:** DEFAULT SET (1 image)

## Summary Table

| Provider | Cold (s) | Warm (s) | Images Generated | Total Size (MB) | Avg Size (KB) |
| --- | ---: | ---: | ---: | ---: | ---: |
| SHARP | 10.24 | 0.13 | 20 | 18.23 | 933.26 |
| LIBVIPS | 7.09 | 0.13 | 20 | 18.41 | 942.84 |
| IMAGEMAGICK | 5.86 | 0.14 | 20 | 14.05 | 719.12 |
| IMGPROXY | 3.17 | 0.12 | 20 | 13.22 | 676.73 |
| WESERV | 7.49 | 0.16 | 20 | 18.46 | 945.09 |
| FLYIMG | 0.43 | 0.17 | 16 | 10.51 | 672.69 |

## Cache Performance

| Provider | Cold Misses | Warm Hits | Warm Misses | Warm Hit Rate (%) |
| --- | ---: | ---: | ---: | ---: |
| SHARP | 20 | 56 | 0 | 100.0 |
| LIBVIPS | 20 | 56 | 0 | 100.0 |
| IMAGEMAGICK | 20 | 56 | 0 | 100.0 |
| IMGPROXY | 20 | 56 | 0 | 100.0 |
| WESERV | 20 | 56 | 0 | 100.0 |
| FLYIMG | 16 | 48 | 0 | 100.0 |

## Processing Time by Primary Operation (s)

| Provider | resize |
| --- | ---: |
| SHARP | 10.032 |
| LIBVIPS | 6.908 |
| IMAGEMAGICK | 5.692 |
| IMGPROXY | 3.002 |
| WESERV | 7.296 |
| FLYIMG | 0.158 |

## Compression Ratio by Format (% saved)

| Provider | avif | jpg | png | webp |
| --- | ---: | ---: | ---: | ---: |
| SHARP | 93.2% | 93.5% | 20.3% | 94.2% |
| LIBVIPS | 93.0% | 92.9% | 20.1% | 94.1% |
| IMAGEMAGICK | 91.4% | 90.0% | 49.1% | 93.3% |
| IMGPROXY | 93.0% | 93.2% | 47.7% | 94.4% |
| WESERV | 91.9% | 93.5% | 20.3% | 94.2% |
| FLYIMG | 92.7% | 93.9% | 47.7% | 94.5% |

## Test Library Information

**Total Input Library Size:** 3.69 MB
**Number of Test Images:** 1
**Test Sizes:** 400, 800, 1200, 1600px
**Output Formats:** avif, webp, png, jpg

## Key Findings

- **Fastest Provider:** flyimg
- **Total Processing Time:** 34.28s

---

*This report was generated automatically by the ImgFlow performance benchmark test.*
