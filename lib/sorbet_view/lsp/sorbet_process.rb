# typed: strict
# frozen_string_literal: true

module SorbetView
  module Lsp
    # Manages Sorbet LSP as a child process
    class SorbetProcess
      extend T::Sig

      sig { returns(T.nilable(Transport)) }
      attr_reader :transport

      sig { params(config: Configuration, logger: Logger).void }
      def initialize(config:, logger:)
        @config = config
        @logger = logger
        @process = T.let(nil, T.nilable(IO))
        @pid = T.let(nil, T.nilable(Integer))
        @transport = T.let(nil, T.nilable(Transport))
        @read_thread = T.let(nil, T.nilable(Thread))
        @notification_handlers = T.let({}, T::Hash[String, T.proc.params(msg: T::Hash[String, T.untyped]).void])
        @pending_requests = T.let({}, T::Hash[T.untyped, Thread::Queue])
        @pending_mutex = T.let(Mutex.new, Mutex)
        @next_id = T.let(1, Integer)
      end

      sig { params(extra_args: T::Array[String]).void }
      def start(extra_args: [])
        cmd = [
          @config.sorbet_path,
          'tc',
          '--lsp',
          '--enable-all-experimental-lsp-features',
          *@config.sorbet_options,
          *extra_args
        ]

        @logger.info("Starting Sorbet: #{cmd.join(' ')}")

        stdin_r, stdin_w = IO.pipe
        stdout_r, stdout_w = IO.pipe
        err_r, err_w = IO.pipe

        @pid = Process.spawn(
          *cmd,
          in: stdin_r,
          out: stdout_w,
          err: err_w
        )

        stdin_r.close
        stdout_w.close
        err_w.close

        @process = stdin_w
        @transport = Transport.new(input: stdout_r, output: stdin_w)

        @read_thread = Thread.new { read_loop(stdout_r) }

        # Log stderr from Sorbet in background
        Thread.new do
          err_r.each_line { |line| @logger.info("Sorbet stderr: #{line.chomp}") }
          err_r.close
        end
      end

      sig { params(method_name: String, params: T.untyped).returns(T.untyped) }
      def send_request(method_name, params)
        transport = @transport
        raise 'Sorbet process not started' unless transport

        id = @pending_mutex.synchronize do
          current = @next_id
          @next_id += 1
          current
        end

        queue = Thread::Queue.new
        @pending_mutex.synchronize { @pending_requests[id] = queue }

        transport.send_request(id, method_name, params)

        # Wait for response with timeout
        result = nil
        deadline = Time.now + 30
        loop do
          break unless result.nil?
          break if Time.now > deadline

          begin
            result = queue.pop(true) # non-blocking
          rescue ThreadError
            sleep 0.05
          end
        end

        @pending_mutex.synchronize { @pending_requests.delete(id) }

        if result.nil?
          @logger.error("Sorbet request '#{method_name}' timed out (30s)")
        end

        result
      end

      sig { params(method_name: String, params: T.untyped).void }
      def send_notification(method_name, params)
        transport = @transport
        raise 'Sorbet process not started' unless transport

        transport.send_notification(method_name, params)
      end

      # Forward a raw message (request or notification) to Sorbet
      sig { params(message: T::Hash[String, T.untyped]).void }
      def forward(message)
        transport = @transport
        raise 'Sorbet process not started' unless transport

        transport.write_message(message)
      end

      sig { params(method_name: String, block: T.proc.params(msg: T::Hash[String, T.untyped]).void).void }
      def on_notification(method_name, &block)
        @notification_handlers[method_name] = block
      end

      sig { void }
      def stop
        if @pid
          Process.kill('TERM', @pid)
          Process.wait(@pid)
          @pid = nil
        end
        @read_thread&.kill
      rescue Errno::ESRCH, Errno::ECHILD
        # Process already gone
      end

      private

      sig { params(stdout: IO).void }
      def read_loop(stdout)
        reader = Transport.new(input: stdout, output: File.open(File::NULL, 'w'))
        loop do
          message = reader.read_message
          break if message.nil?

          if message['id'] && !message.key?('method')
            # Response to our request
            @pending_mutex.synchronize do
              queue = @pending_requests[message['id']]
              queue&.push(message)
            end
          elsif message.key?('method')
            # Notification from Sorbet
            handler = @notification_handlers[message['method']]
            handler&.call(message)
          end
        end
      rescue IOError
        @logger.info('Sorbet process stdout closed')
      end
    end
  end
end
