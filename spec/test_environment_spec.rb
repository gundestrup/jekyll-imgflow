# frozen_string_literal: true

require "spec_helper"

RSpec.describe TestEnvironment, :unit do
  describe "provider port blocks" do
    it "uses the test env file for Docker service ports" do
      expect(described_class.docker_url("imgproxy")).to eq(
        "http://localhost:#{described_class.docker_port_for('imgproxy')}"
      )
      expect(described_class.docker_url("weserv")).to eq(
        "http://localhost:#{described_class.docker_port_for('weserv')}"
      )
      expect(described_class.docker_url("flyimg")).to eq(
        "http://localhost:#{described_class.docker_port_for('flyimg')}"
      )
    end

    it "assigns source and reserve ports after each provider base" do
      TestEnvironment::HTTP_PROVIDERS.each do |provider|
        base = described_class.docker_port_for(provider)
        expect(described_class.source_port_for(provider)).to eq(base + 1)
        expect(described_class.source_port_for(provider, :reserve)).to eq(base + 2)
      end
    end

    it "does not allocate development port 4000" do
      expect(described_class.all_test_ports).not_to include(4000)
      expect(described_class.current_source_port).not_to eq(4000)
    end

    it "does not assign source ports to CLI providers" do
      TestEnvironment::CLI_PROVIDERS.each do |provider|
        expect(described_class.source_port_for(provider)).to be_nil
      end
    end
  end

  describe "source server selection" do
    it "uses localhost for ordinary CLI tests" do
      expect(described_class.site_url(provider: "sharp")).to start_with("http://localhost:")
    end
  end
end
