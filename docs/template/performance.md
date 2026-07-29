# ImgFlow Performance Benchmark Template

This template defines the structure for performance benchmark reports.

## Report Structure

```markdown
# ImgFlow Performance Benchmark Report

**Generated:** TIMESTAMP
**Ruby Version:** RUBY_VERSION
**Operating System:** OS
**CPU:** CPU_INFO
**Memory:** MEMORY_INFO

## Test Images

| Name | Description | Dimensions | Original Size |
|------|-------------|------------|---------------|
| IMAGE_TABLE_ROWS

## Provider Performance

### PROVIDER_NAME

#### FORMAT_NAME Format

- **Total Processing Time:** TIME_SECONDS
- **Total Original Size:** SIZE_MB
- **Total Processed Size:** SIZE_MB
- **Average Compression:** PERCENTAGE%

| Size | Time (s) | Original (MB) | Processed (MB) | Compression |
|------|----------|----------------|-----------------|------------|
| SIZE_TABLE_ROWS

## Summary

### Key Findings

- **Fastest Provider:** PROVIDER_NAME
- **Best Compression:** PROVIDER_NAME
- **Total Images Processed:** COUNT

### Recommendations

Based on this benchmark:

1. **For Speed:** Use PROVIDER_NAME provider
2. **For Compression:** Use PROVIDER_NAME provider
3. **For Balance:** Consider your specific use case requirements

### Test Environment Notes

- This benchmark was run on a OS system
- Results may vary based on hardware configuration
- Consider running multiple tests for more accurate averages
```

## Data Structure

The benchmark script collects the following data:

```ruby
{
  run_info: {
    timestamp: "2026-03-14T07:30:00+01:00",
    ruby_version: "3.2.7",
    os: "x86_64-darwin23",
    cpu: "Apple M1 Pro",
    memory: "16.0 GB"
  },
  test_images: [
    {
      name: "small-square",
      description: "Small square image",
      dimensions: "100x100",
      original_size_bytes: 1024,
      original_size_mb: 0.001
    }
  ],
  providers: {
    "libvips" => {
      total_time: 15.23,
      images_processed: 16,
      formats: {
        "webp" => {
          total_time: 3.45,
          total_size_original: 1048576,
          total_size_processed: 524288,
          compression_ratio: 50.0,
          sizes: {
            400 => {
              time: 0.123,
              original_size: 262144,
              processed_size: 131072,
              compression_ratio: 50.0,
              filename: "small-square-400-abc123.webp"
            }
          },
          errors: []
        }
      },
      errors: []
    }
  },
  summary: {
    fastest_provider: "libvips",
    best_compression: "avif",
    total_processed: 32
  }
}
```

## Metrics Collected

### Time Metrics
- **Processing Time:** Time taken to convert each image
- **Total Time:** Aggregate time for all conversions
- **Per-provider Time:** Time per provider and format

### Size Metrics
- **Original Size:** Size of source images
- **Processed Size:** Size of converted images
- **Compression Ratio:** Percentage of size reduction
- **Format Efficiency:** Comparison between formats

### System Metrics
- **CPU Information:** Processor type and speed
- **Memory:** Available system memory
- **Operating System:** Platform and version
- **Ruby Version:** Ruby interpreter version

## Test Images

The benchmark uses standardized test images:

1. **Small Square:** 100x100px - Tests small image performance
2. **Medium Landscape:** 800x600px - Tests typical web image
3. **Large Portrait:** 1200x1600px - Tests large image handling
4. **Ultra-Wide:** 2000x800px - Tests wide format processing

## Output Formats

Each image is converted to:
- **WebP:** Modern web format with good compression
- **AVIF:** Next-gen format with best compression
- **JPEG:** Standard format for compatibility
- **PNG:** Lossless format for comparison

## Target Sizes

Each format is tested at multiple sizes:
- **400px:** Small thumbnails
- **800px:** Standard web size
- **1200px:** Large web images
- **1600px:** High-resolution images

## Usage

Run the benchmark:
```bash
ruby performance_benchmark.rb
```

The report will be saved as `README.Performance.md` in the current directory.
