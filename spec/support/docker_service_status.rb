# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "timeout"
require "uri"

module DockerServiceStatus
  SERVICE_PATHS = {
    "imgproxy" => "/health",
    "weserv" => "/",
    "flyimg" => "/"
  }.freeze

  module_function

  def services
    SERVICE_PATHS.map do |name, health_path|
      {
        name: name,
        port: TestEnvironment.docker_port_for(name),
        health_path: health_path
      }
    end
  end

  def container_status(name, compose_file:, env_file:)
    stdout, stderr, status = Open3.capture3(
      "docker-compose", "-f", compose_file, "--env-file", env_file,
      "ps", "--all", "--format", "json", name
    )
    return { state: "unavailable", detail: stderr.strip } unless status.success?

    record = parse_compose_record(stdout)
    return { state: "missing", detail: "container has not been created" } unless record

    {
      state: (record["State"] || "unknown").downcase,
      health: record["Health"].to_s.downcase,
      exit_code: record["ExitCode"],
      detail: record["Status"].to_s
    }
  rescue Errno::ENOENT => e
    { state: "unavailable", detail: e.message }
  end

  def http_status(service)
    uri = URI("http://localhost:#{service[:port]}#{service[:health_path]}")
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 2) do |http|
      http.get(uri.request_uri)
    end
    {
      healthy: response.code.to_i.between?(200, 299),
      detail: "HTTP #{response.code}"
    }
  rescue StandardError => e
    { healthy: false, detail: e.message }
  end

  def statuses(compose_file:, env_file:)
    services.to_h do |service|
      container = container_status(service[:name], compose_file: compose_file, env_file: env_file)
      [service[:name], { service: service, container: container, http: http_status(service) }]
    end
  end

  def wait(compose_file:, env_file:, timeout: 90, interval: 1)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      current = statuses(compose_file: compose_file, env_file: env_file)
      return { ready: true, statuses: current } if current.values.all? { |item| ready?(item) }
      return { ready: false, statuses: current } if current.values.any? { |item| failed?(item) }
      return { ready: false, statuses: current } if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep interval
    end
  end

  def ready?(item)
    item[:container][:state] == "running" && item[:http][:healthy]
  end

  def failed?(item)
    %w[dead exited].include?(item[:container][:state])
  end

  def parse_compose_record(output)
    parsed = JSON.parse(output)
    parsed.is_a?(Array) ? parsed.first : parsed
  rescue JSON::ParserError
    output.each_line.filter_map do |line|
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end.first
  end
end
