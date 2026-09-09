# frozen_string_literal: true

module TestEnvironment
  PROVIDERS = %w[sharp libvips imagemagick imgproxy weserv flyimg].freeze
  CLI_PROVIDERS = %w[sharp libvips imagemagick].freeze
  HTTP_PROVIDERS = %w[imgproxy weserv flyimg].freeze

  PROVIDER_PORT_ENV = {
    "sharp" => "SHARP_PORT",
    "libvips" => "LIBVIPS_PORT",
    "imagemagick" => "IMAGEMAGICK_PORT",
    "imgproxy" => "IMGPROXY_PORT",
    "weserv" => "WESERV_PORT",
    "flyimg" => "FLYIMG_PORT"
  }.freeze

  SPECIAL_PORT_ENV = {
    cross_provider: "CROSS_PROVIDER_PORT",
    performance: "PERFORMANCE_PORT",
    general: "GENERAL_TEST_PORT"
  }.freeze

  SLOT_OFFSETS = {
    docker: 0,
    source: 1,
    primary: 1,
    reserve: 2,
    secondary: 2,
    spare: 3
  }.freeze

  class << self
    def configured_providers(config = nil)
      config ||= TEST_CONFIG if defined?(TEST_CONFIG)
      configured = config&.dig("imgflow", "backend_priority")
      configured && !configured.empty? ? configured : PROVIDERS
    end

    def providers_for_test(config = nil)
      filter = ENV.fetch("IMGFLOW_TEST_PROVIDER", nil)
      return [filter] if filter && !filter.empty?

      configured_providers(config)
    end

    def http_provider?(provider)
      HTTP_PROVIDERS.include?(provider.to_s.downcase)
    end

    def cli_provider?(provider)
      CLI_PROVIDERS.include?(provider.to_s.downcase)
    end

    def block_base_for(provider)
      port_value(PROVIDER_PORT_ENV.fetch(provider.to_s.downcase))
    end

    def port_for(provider, slot = :source)
      block_base_for(provider) + SLOT_OFFSETS.fetch(slot.to_sym)
    end

    def docker_port_for(provider)
      port_for(provider, :docker)
    end

    def source_port_for(provider, slot = :primary)
      return nil unless http_provider?(provider)

      port_for(provider, slot)
    end

    def special_port_for(name, slot = :source)
      port_value(SPECIAL_PORT_ENV.fetch(name.to_sym)) + SLOT_OFFSETS.fetch(slot.to_sym)
    end

    def source_server_mode
      explicit = ENV.fetch("IMGFLOW_TEST_SOURCE_SERVER", nil)
      return explicit.to_sym if explicit && !explicit.empty?
      return :webrick if ENV.fetch("IMGFLOW_TEST_HTTP", nil) == "true"
      return :webrick if http_provider?(ENV.fetch("IMGFLOW_TEST_PROVIDER", nil))

      :none
    end

    def source_server_required?
      source_server_mode != :none
    end

    def current_source_port
      explicit = ENV.fetch("IMGFLOW_TEST_PORT", nil)
      return explicit.to_i if explicit && !explicit.empty?

      provider = ENV.fetch("IMGFLOW_TEST_PROVIDER", nil)
      if http_provider?(provider)
        slot = ENV.fetch("IMGFLOW_TEST_SOURCE_SLOT", "primary").to_sym
        return source_port_for(provider, slot)
      end
      return block_base_for(provider) if provider && PROVIDER_PORT_ENV.key?(provider)

      case source_server_mode
      when :cross_provider
        special_port_for(:cross_provider, :source)
      when :performance
        special_port_for(:performance, :source)
      else
        special_port_for(:general, :source) + ENV.fetch("TEST_ENV_NUMBER", "0").to_i
      end
    end

    def site_url(provider: nil, port: nil)
      port ||= if !source_server_required? && provider &&
                  PROVIDER_PORT_ENV.key?(provider.to_s.downcase)
                 provider_site_port(provider)
               else
                 current_source_port
               end
      host = if source_server_required? || http_provider?(provider)
               "host.docker.internal"
             else
               "localhost"
             end
      "http://#{host}:#{port}"
    end

    def provider_site_port(provider)
      http_provider?(provider) ? source_port_for(provider) : block_base_for(provider)
    end

    def docker_url(provider)
      "http://localhost:#{docker_port_for(provider)}"
    end

    def start_source_server
      return @source_server if @source_server
      return unless source_server_mode == :webrick

      require "webrick"
      project_root = File.expand_path("../..", __dir__)
      port = current_source_port
      server = WEBrick::HTTPServer.new(
        BindAddress: "0.0.0.0",
        Port: port,
        Logger: WEBrick::Log.new(File::NULL),
        AccessLog: []
      )
      server.mount_proc("/") do |request, response|
        relative_path = request.path_info.delete_prefix("/")
        candidates = [project_root, "/", "/tmp"]
        tests_dir = File.join(project_root, "tmp", "tests")
        candidates.concat(Dir.glob(File.join(tests_dir, "*"))) if Dir.exist?(tests_dir)
        file = candidates.map { |root| File.join(root, relative_path) }
                         .find { |candidate| File.file?(candidate) }

        if file
          response.body = File.binread(file)
          response["content-type"] = WEBrick::HTTPUtils.mime_type(
            file, WEBrick::HTTPUtils::DefaultMimeTypes
          )
        else
          response.status = 404
          response.body = "Not found: #{request.path_info}"
        end
      end

      @source_server = server
      @source_server_thread = Thread.new { server.start }
      sleep 1
      server
    end

    def stop_source_server
      @source_server&.shutdown
      @source_server_thread&.join(1)
      @source_server = nil
      @source_server_thread = nil
    end

    def all_test_ports
      provider_ports = PROVIDER_PORT_ENV.keys.flat_map do |provider|
        base = block_base_for(provider)
        (base...(base + port_block_size)).to_a
      end
      special_ports = SPECIAL_PORT_ENV.keys.flat_map do |name|
        base = port_value(SPECIAL_PORT_ENV.fetch(name))
        (base...(base + port_block_size)).to_a
      end
      provider_ports + special_ports
    end

    private

    def port_block_size
      port_value("TEST_PORT_BLOCK_SIZE")
    end

    def port_value(name)
      value = ENV.fetch(name, nil) || env_file_values.fetch(name, nil)
      raise "Missing #{name} in .env.test" unless value && !value.empty?

      Integer(value, 10)
    end

    def env_file_values
      @env_file_values ||= begin
        path = File.expand_path("../../.env.test", __dir__)
        File.foreach(path).filter_map do |line|
          match = line.chomp.match(/\A([A-Za-z_][A-Za-z0-9_]*)=(.*)\z/)
          next unless match

          [match[1], match[2].strip.delete_prefix('"').delete_suffix('"')]
        end.to_h
      end
    end
  end
end
