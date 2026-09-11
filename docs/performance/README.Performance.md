# Enhanced ImgFlow Performance Benchmark Report (DEFAULT SET)

**Generated:** 2026-09-11T09:25:26+0200
**Ruby Version:** 3.4.10
**Operating System:** macOS 26.6.2
**CPU:** Apple M2
**Memory:** 24.0 GB
**CPU Cores:** 8 total, 7 used for testing
**Test Set:** DEFAULT SET (1 image)

## Summary Table

| Provider | Cold (s) | Warm (s) | Images Generated | Total Size (MB) | Avg Size (KB) |
| --- | ---: | ---: | ---: | ---: | ---: |
| SHARP | 1543.11 | 0.91 | 20 | 18.23 | 933.26 |
| LIBVIPS | 17.19 | 0.14 | 20 | 18.41 | 942.84 |
| IMAGEMAGICK | 6.16 | 0.15 | 20 | 14.05 | 719.12 |
| IMGPROXY | 3.36 | 0.14 | 20 | 13.22 | 676.73 |
| WESERV | 3.05 | 0.16 | 20 | 18.46 | 945.09 |
| FLYIMG | 2.4 | 0.15 | 20 | 15.42 | 789.32 |

## Cache Performance

| Provider | Cold Misses | Warm Hits | Warm Misses | Warm Hit Rate (%) |
| --- | ---: | ---: | ---: | ---: |
| SHARP | 20 | 56 | 0 | 100.0 |
| LIBVIPS | 20 | 56 | 0 | 100.0 |
| IMAGEMAGICK | 20 | 56 | 0 | 100.0 |
| IMGPROXY | 20 | 56 | 0 | 100.0 |
| WESERV | 20 | 56 | 0 | 100.0 |
| FLYIMG | 20 | 56 | 0 | 100.0 |

## Processing Time by Primary Operation (s)

| Provider | resize |
| --- | ---: |
| SHARP | 1542.716 |
| LIBVIPS | 16.48 |
| IMAGEMAGICK | 5.983 |
| IMGPROXY | 3.178 |
| WESERV | 2.865 |
| FLYIMG | 2.179 |

## Compression Ratio by Format (% saved)

| Provider | avif | jpg | png | webp |
| --- | ---: | ---: | ---: | ---: |
| SHARP | 93.2% | 93.5% | 20.3% | 94.2% |
| LIBVIPS | 93.0% | 92.9% | 20.1% | 94.1% |
| IMAGEMAGICK | 91.4% | 90.0% | 49.1% | 93.3% |
| IMGPROXY | 93.0% | 93.2% | 47.7% | 94.4% |
| WESERV | 91.9% | 93.5% | 20.3% | 94.2% |
| FLYIMG | 91.0% | 91.6% | 40.8% | 93.1% |

## Test Library Information

**Total Input Library Size:** 3.69 MB
**Number of Test Images:** 1
**Test Sizes:** 400, 800, 1200, 1600px
**Output Formats:** avif, webp, png, jpg

## Key Findings

- **Fastest Provider:** flyimg
- **Total Processing Time:** 1575.27s

---

*This report was generated automatically by the ImgFlow performance benchmark test.*
