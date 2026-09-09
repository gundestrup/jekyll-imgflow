# frozen_string_literal: true

require "spec_helper"

RSpec.describe JekyllImgFlow::ProcessingStats, :unit do
  let(:stats) { described_class.new }

  describe "#initialize" do
    it "starts with zero cache hits and misses" do
      expect(stats.cache_hits).to eq(0)
      expect(stats.cache_misses).to eq(0)
    end

    it "starts with empty operation timings" do
      expect(stats.operation_timings).to be_empty
    end

    it "starts with empty compression ratios" do
      expect(stats.compression_ratios).to be_empty
    end
  end

  describe "#record_cache_hit" do
    it "increments the hit counter" do
      stats.record_cache_hit
      expect(stats.cache_hits).to eq(1)
    end

    it "increments multiple times" do
      5.times { stats.record_cache_hit }
      expect(stats.cache_hits).to eq(5)
    end

    it "does not affect misses" do
      stats.record_cache_hit
      expect(stats.cache_misses).to eq(0)
    end
  end

  describe "#record_cache_miss" do
    it "increments the miss counter" do
      stats.record_cache_miss
      expect(stats.cache_misses).to eq(1)
    end

    it "increments multiple times" do
      3.times { stats.record_cache_miss }
      expect(stats.cache_misses).to eq(3)
    end

    it "does not affect hits" do
      stats.record_cache_miss
      expect(stats.cache_hits).to eq(0)
    end
  end

  describe "#record_operation_time" do
    it "accumulates time for a single operation type" do
      stats.record_operation_time(:resize, 1.5)
      stats.record_operation_time(:resize, 2.5)
      expect(stats.operation_timings[:resize]).to eq(4.0)
    end

    it "tracks multiple operation types independently" do
      stats.record_operation_time(:resize, 1.0)
      stats.record_operation_time(:format, 0.5)
      stats.record_operation_time(:resize, 2.0)
      stats.record_operation_time(:quality, 0.3)
      expect(stats.operation_timings[:resize]).to eq(3.0)
      expect(stats.operation_timings[:format]).to eq(0.5)
      expect(stats.operation_timings[:quality]).to eq(0.3)
    end

    it "handles zero-duration operations" do
      stats.record_operation_time(:resize, 0.0)
      expect(stats.operation_timings[:resize]).to eq(0.0)
    end
  end

  describe "#record_compression_ratio" do
    it "records a single compression ratio" do
      stats.record_compression_ratio("webp", 1000, 300)
      expect(stats.average_compression_ratios["webp"]).to eq(70.0)
    end

    it "averages multiple ratios for the same format" do
      stats.record_compression_ratio("webp", 1000, 400) # 60%
      stats.record_compression_ratio("webp", 1000, 200) # 80%
      expect(stats.average_compression_ratios["webp"]).to eq(70.0)
    end

    it "tracks multiple formats independently" do
      stats.record_compression_ratio("webp", 1000, 300) # 70%
      stats.record_compression_ratio("avif", 1000, 200) # 80%
      expect(stats.average_compression_ratios["webp"]).to eq(70.0)
      expect(stats.average_compression_ratios["avif"]).to eq(80.0)
    end

    it "ignores zero original size to avoid division by zero" do
      stats.record_compression_ratio("webp", 0, 100)
      expect(stats.average_compression_ratios).to be_empty
    end

    it "handles output larger than original (negative compression)" do
      stats.record_compression_ratio("png", 100, 200)
      expect(stats.average_compression_ratios["png"]).to eq(-100.0)
    end

    it "handles identical input and output sizes (0% compression)" do
      stats.record_compression_ratio("jpg", 500, 500)
      expect(stats.average_compression_ratios["jpg"]).to eq(0.0)
    end
  end

  describe "#total_processed" do
    it "returns zero when nothing has been recorded" do
      expect(stats.total_processed).to eq(0)
    end

    it "returns the sum of hits and misses" do
      3.times { stats.record_cache_hit }
      2.times { stats.record_cache_miss }
      expect(stats.total_processed).to eq(5)
    end
  end

  describe "#cache_hit_rate" do
    it "returns 0.0 when nothing has been processed" do
      expect(stats.cache_hit_rate).to eq(0.0)
    end

    it "returns 100.0 when all operations are cache hits" do
      5.times { stats.record_cache_hit }
      expect(stats.cache_hit_rate).to eq(100.0)
    end

    it "returns 0.0 when all operations are cache misses" do
      5.times { stats.record_cache_miss }
      expect(stats.cache_hit_rate).to eq(0.0)
    end

    it "returns the correct percentage for a mix" do
      3.times { stats.record_cache_hit }
      7.times { stats.record_cache_miss }
      expect(stats.cache_hit_rate).to eq(30.0)
    end

    it "rounds to one decimal place" do
      stats.record_cache_hit
      2.times { stats.record_cache_miss }
      # 1/3 = 33.333... → 33.3
      expect(stats.cache_hit_rate).to eq(33.3)
    end
  end

  describe "#to_h" do
    it "returns a hash with all metrics" do
      stats.record_cache_hit
      stats.record_cache_miss
      stats.record_operation_time(:resize, 1.5)
      stats.record_compression_ratio("webp", 1000, 400)

      hash = stats.to_h
      expect(hash).to include(
        cache_hits: 1,
        cache_misses: 1,
        cache_hit_rate: 50.0,
        total_processed: 2,
        operation_timings: { resize: 1.5 },
        compression_ratios: { "webp" => 60.0 }
      )
    end

    it "rounds operation timings to 3 decimal places" do
      stats.record_operation_time(:resize, 1.23456)
      expect(stats.to_h[:operation_timings][:resize]).to eq(1.235)
    end

    it "returns safe defaults for an empty stats object" do
      hash = stats.to_h
      expect(hash[:cache_hits]).to eq(0)
      expect(hash[:cache_misses]).to eq(0)
      expect(hash[:cache_hit_rate]).to eq(0.0)
      expect(hash[:total_processed]).to eq(0)
      expect(hash[:operation_timings]).to be_empty
      expect(hash[:compression_ratios]).to be_empty
    end
  end

  describe "#reset" do
    it "clears all counters" do
      stats.record_cache_hit
      stats.record_cache_miss
      stats.record_operation_time(:resize, 1.0)
      stats.record_compression_ratio("webp", 1000, 500)

      stats.reset

      expect(stats.cache_hits).to eq(0)
      expect(stats.cache_misses).to eq(0)
      expect(stats.operation_timings).to be_empty
      expect(stats.compression_ratios).to be_empty
      expect(stats.total_processed).to eq(0)
      expect(stats.cache_hit_rate).to eq(0.0)
    end

    it "allows recording after reset" do
      stats.record_cache_hit
      stats.reset
      stats.record_cache_hit
      expect(stats.cache_hits).to eq(1)
    end
  end

  describe "thread safety" do
    it "handles concurrent cache hit increments without losing counts" do
      threads = Array.new(4) do
        Thread.new do
          100.times { stats.record_cache_hit }
        end
      end
      threads.each(&:join)
      expect(stats.cache_hits).to eq(400)
    end

    it "handles concurrent mixed operations" do
      threads = Array.new(4) do |i|
        Thread.new do
          50.times do
            stats.record_cache_hit if i.even?
            stats.record_cache_miss if i.odd?
            stats.record_operation_time(:resize, 0.01)
          end
        end
      end
      threads.each(&:join)
      expect(stats.total_processed).to eq(200)
      expect(stats.operation_timings[:resize]).to be_within(0.001).of(2.0)
    end
  end
end
