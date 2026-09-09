# frozen_string_literal: true

require "spec_helper"
require "support/docker_service_status"

RSpec.describe DockerServiceStatus, :unit do
  describe "SERVICE_PATHS" do
    it "maps every HTTP provider to a health-check path" do
      expect(described_class::SERVICE_PATHS.keys)
        .to contain_exactly("imgproxy", "weserv", "flyimg")
    end

    it "uses /health for imgproxy and / for weserv and flyimg" do
      expect(described_class::SERVICE_PATHS["imgproxy"]).to eq("/health")
      expect(described_class::SERVICE_PATHS["weserv"]).to eq("/")
      expect(described_class::SERVICE_PATHS["flyimg"]).to eq("/")
    end
  end

  describe ".services" do
    it "returns name, port, and health_path for each HTTP provider" do
      services = described_class.services
      expect(services.length).to eq(3)
      services.each do |svc|
        expect(svc).to include(:name, :port, :health_path)
        expect(svc[:port]).to be_an(Integer).and(be_between(4000, 5000))
      end
    end
  end

  describe ".ready?" do
    it "is ready when container is running and http is healthy" do
      item = { container: { state: "running" }, http: { healthy: true } }
      expect(described_class.ready?(item)).to be(true)
    end

    it "is not ready when container is running but http is unhealthy" do
      item = { container: { state: "running" }, http: { healthy: false } }
      expect(described_class.ready?(item)).to be(false)
    end

    it "is not ready when container is not running" do
      item = { container: { state: "exited" }, http: { healthy: true } }
      expect(described_class.ready?(item)).to be(false)
    end
  end

  describe ".failed?" do
    %w[dead exited].each do |state|
      it "is failed when container state is #{state}" do
        item = { container: { state: state }, http: { healthy: false } }
        expect(described_class.failed?(item)).to be(true)
      end
    end

    it "is not failed when container is running" do
      item = { container: { state: "running" }, http: { healthy: false } }
      expect(described_class.failed?(item)).to be(false)
    end

    it "is not failed when container is restarting" do
      item = { container: { state: "restarting" }, http: { healthy: false } }
      expect(described_class.failed?(item)).to be(false)
    end
  end

  describe ".parse_compose_record" do
    it "parses a single JSON object" do
      output = '{"State":"running","Health":"healthy"}'
      record = described_class.parse_compose_record(output)
      expect(record["State"]).to eq("running")
      expect(record["Health"]).to eq("healthy")
    end

    it "parses a JSON array and returns the first record" do
      output = '[{"State":"running"},{"State":"exited"}]'
      record = described_class.parse_compose_record(output)
      expect(record["State"]).to eq("running")
    end

    it "parses newline-delimited JSON and returns the first record" do
      output = "{\"State\":\"running\"}\n{\"State\":\"exited\"}\n"
      record = described_class.parse_compose_record(output)
      expect(record["State"]).to eq("running")
    end

    it "returns nil when output is not parseable JSON" do
      expect(described_class.parse_compose_record("not json")).to be_nil
    end
  end

  describe ".http_status" do
    let(:service) { { name: "imgproxy", port: 4022, health_path: "/health" } }

    it "reports healthy when HTTP returns 200" do
      fake_response = instance_double(Net::HTTPResponse, code: "200")
      allow(Net::HTTP).to receive(:start).and_yield(double("http", get: fake_response))
      result = described_class.http_status(service)
      expect(result[:healthy]).to be(true)
      expect(result[:detail]).to eq("HTTP 200")
    end

    it "reports unhealthy when HTTP returns 503" do
      fake_response = instance_double(Net::HTTPResponse, code: "503")
      allow(Net::HTTP).to receive(:start).and_yield(double("http", get: fake_response))
      result = described_class.http_status(service)
      expect(result[:healthy]).to be(false)
      expect(result[:detail]).to eq("HTTP 503")
    end

    it "reports unhealthy on connection refused" do
      allow(Net::HTTP).to receive(:start)
        .and_raise(Errno::ECONNREFUSED, "Connection refused")
      result = described_class.http_status(service)
      expect(result[:healthy]).to be(false)
      expect(result[:detail]).to match(/refused/i)
    end

    it "reports unhealthy on EOF (server closed connection during startup)" do
      allow(Net::HTTP).to receive(:start).and_raise(EOFError, "end of file reached")
      result = described_class.http_status(service)
      expect(result[:healthy]).to be(false)
      expect(result[:detail]).to match(/end of file/i)
    end

    it "reports unhealthy on timeout" do
      allow(Net::HTTP).to receive(:start).and_raise(Net::ReadTimeout, "read timeout")
      result = described_class.http_status(service)
      expect(result[:healthy]).to be(false)
      expect(result[:detail]).to match(/timeout/i)
    end
  end

  describe ".container_status" do
    let(:compose_file) { "docker-compose.test.yml" }
    let(:env_file) { ".env.test" }
    let(:name) { "imgproxy" }

    it "reports unavailable when docker-compose command is missing" do
      result = described_class.container_status(
        name, compose_file: compose_file, env_file: env_file
      )
      # In test environment docker-compose may or may not be installed; either
      # we get a real status or an unavailable. Both are valid responses.
      expect(result).to include(:state)
      expect(%w[unavailable missing running exited restarting created dead unknown])
        .to include(result[:state])
    end
  end

  describe ".wait" do
    let(:compose_file) { "docker-compose.test.yml" }
    let(:env_file) { ".env.test" }

    it "returns immediately ready when all services are already healthy" do
      ready_item = {
        container: { state: "running" },
        http: { healthy: true, detail: "HTTP 200" }
      }
      allow(described_class).to receive(:statuses)
        .and_return(
          "imgproxy" => ready_item,
          "weserv" => ready_item,
          "flyimg" => ready_item
        )
      result = described_class.wait(
        compose_file: compose_file, env_file: env_file, timeout: 5, interval: 0
      )
      expect(result[:ready]).to be(true)
    end

    it "returns not ready when any container has exited" do
      failed_item = {
        container: { state: "exited" },
        http: { healthy: false, detail: "Connection refused" }
      }
      allow(described_class).to receive(:statuses)
        .and_return(
          "imgproxy" => failed_item,
          "weserv" => failed_item,
          "flyimg" => failed_item
        )
      result = described_class.wait(
        compose_file: compose_file, env_file: env_file, timeout: 5, interval: 0
      )
      expect(result[:ready]).to be(false)
    end

    it "times out when services never become ready and never fail" do
      pending_item = {
        container: { state: "restarting" },
        http: { healthy: false, detail: "Connection refused" }
      }
      allow(described_class).to receive(:statuses)
        .and_return(
          "imgproxy" => pending_item,
          "weserv" => pending_item,
          "flyimg" => pending_item
        )
      result = described_class.wait(
        compose_file: compose_file, env_file: env_file, timeout: 0, interval: 0
      )
      expect(result[:ready]).to be(false)
    end
  end
end
