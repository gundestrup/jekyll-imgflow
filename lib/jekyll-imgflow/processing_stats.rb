# frozen_string_literal: true

module JekyllImgFlow
  # ProcessingStats — collects cache hit/miss, per-operation timing, and
  # compression ratio metrics during a Jekyll build. Accessed by the
  # performance benchmark to report beyond wall-clock time.
  class ProcessingStats
    attr_reader :cache_hits, :cache_misses, :operation_timings, :compression_ratios

    def initialize
      @cache_hits = 0
      @cache_misses = 0
      @operation_timings = Hash.new { |h, k| h[k] = 0.0 }
      @compression_ratios = {}
      @mutex = Mutex.new
    end

    def record_cache_hit
      @mutex.synchronize { @cache_hits += 1 }
    end

    def record_cache_miss
      @mutex.synchronize { @cache_misses += 1 }
    end

    # Record wall-clock time for a specific operation type (:resize, :format, etc.)
    def record_operation_time(type, seconds)
      @mutex.synchronize { @operation_timings[type] += seconds }
    end

    # Record compression ratio for a format (e.g. "webp" => 78.5 percent saved)
    def record_compression_ratio(format, original_size, output_size)
      return if original_size.zero?

      ratio = ((original_size - output_size).to_f / original_size * 100).round(1)
      @mutex.synchronize do
        @compression_ratios[format] ||= { ratios: [], count: 0 }
        @compression_ratios[format][:ratios] << ratio
        @compression_ratios[format][:count] += 1
      end
    end

    # Average compression ratio per format
    def average_compression_ratios
      @compression_ratios.transform_values do |data|
        (data[:ratios].sum / data[:count]).round(1) if data[:count].positive?
      end
    end

    def total_processed
      @cache_hits + @cache_misses
    end

    def cache_hit_rate
      return 0.0 if total_processed.zero?

      (@cache_hits.to_f / total_processed * 100).round(1)
    end

    def to_h
      {
        cache_hits: @cache_hits,
        cache_misses: @cache_misses,
        cache_hit_rate: cache_hit_rate,
        total_processed: total_processed,
        operation_timings: @operation_timings.transform_values { |v| v.round(3) },
        compression_ratios: average_compression_ratios
      }
    end

    def reset
      @mutex.synchronize do
        @cache_hits = 0
        @cache_misses = 0
        @operation_timings.clear
        @compression_ratios.clear
      end
    end
  end
end
