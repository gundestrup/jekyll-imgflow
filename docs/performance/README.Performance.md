# Enhanced ImgFlow Performance Benchmark Report (DEFAULT SET)

**Generated:** 2026-09-08T08:32:14+0200
**Ruby Version:** 3.4.10
**Operating System:** macOS 26.6.2
**CPU:** Apple M2
**Memory:** 24.0 GB
**CPU Cores:** 8 total, 7 used for testing
**Test Set:** DEFAULT SET (1 image)

## Summary Table

| Provider | Cold (s) | Warm (s) | Images Generated | Total Size (MB) | Avg Size (KB) |
| --- | ---: | ---: | ---: | ---: | ---: |
| SHARP | 8.77 | 0.07 | 20 | 18.7 | 957.31 |
| LIBVIPS | 6.97 | 0.07 | 20 | 18.41 | 942.84 |
| IMAGEMAGICK | 5.75 | 0.08 | 20 | 14.05 | 719.12 |

## Cache Performance

| Provider | Cold Misses | Warm Hits | Warm Misses | Warm Hit Rate (%) |
| --- | ---: | ---: | ---: | ---: |
| SHARP | 20 | 33 | 0 | 100.0 |
| LIBVIPS | 20 | 33 | 0 | 100.0 |
| IMAGEMAGICK | 20 | 33 | 0 | 100.0 |

## Processing Time by Primary Operation (s)

| Provider | resize |
| --- | ---: |
| SHARP | 8.664 |
| LIBVIPS | 6.877 |
| IMAGEMAGICK | 5.647 |

## Compression Ratio by Format (% saved)

| Provider | avif | jpg | png | webp |
| --- | ---: | ---: | ---: | ---: |
| SHARP | 90.6% | 93.5% | 20.3% | 94.2% |
| LIBVIPS | 93.0% | 92.9% | 20.1% | 94.1% |
| IMAGEMAGICK | 91.4% | 90.0% | 49.1% | 93.3% |

## Test Library Information

**Total Input Library Size:** 3.69 MB
**Number of Test Images:** 1
**Test Sizes:** 400, 800, 1200, 1600px
**Output Formats:** avif, webp, png, jpg

## Key Findings

- **Fastest Provider:** imagemagick
- **Total Processing Time:** 21.49s

---

*This report was generated automatically by the ImgFlow performance benchmark test.*
