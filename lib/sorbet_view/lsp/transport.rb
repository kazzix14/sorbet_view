# typed: strict
# frozen_string_literal: true

require 'json'
require 'stringio'

module SorbetView
  module Lsp
    # JSON-RPC over stdio transport for LSP
    class Transport
      extend T::Sig

      sig { params(input: T.any(IO, StringIO), output: T.any(IO, StringIO)).void }
      def initialize(input: $stdin, output: $stdout)
        @input = T.let(input, T.any(IO, StringIO))
        @output = T.let(output, T.any(IO, StringIO))
        @mutex = T.let(Mutex.new, Mutex)
      end

      # Read a single JSON-RPC message from the input stream.
      # Returns nil on EOF.
      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def read_message
        # Read headers
        content_length = nil
        loop do
          line = @input.gets
          return nil if line.nil? # EOF

          line = line.strip
          break if line.empty? # End of headers

          if line.start_with?('Content-Length:')
            content_length = line.split(':').last&.strip&.to_i
          end
        end

        return nil unless content_length

        # Read body
        body = @input.read(content_length)
        return nil if body.nil?

        JSON.parse(body)
      end

      # Write a JSON-RPC message to the output stream (thread-safe).
      sig { params(message: T::Hash[String, T.untyped]).void }
      def write_message(message)
        body = JSON.generate(message)
        header = "Content-Length: #{body.bytesize}\r\n\r\n"

        @mutex.synchronize do
          @output.write(header)
          @output.write(body)
          @output.flush
        end
      end

      # Convenience: send a JSON-RPC response
      sig { params(id: T.untyped, result: T.untyped).void }
      def send_response(id, result)
        write_message({ 'jsonrpc' => '2.0', 'id' => id, 'result' => result })
      end

      # Convenience: send a JSON-RPC error response
      sig { params(id: T.untyped, code: Integer, message: String).void }
      def send_error(id, code, message)
        write_message({
          'jsonrpc' => '2.0',
          'id' => id,
          'error' => { 'code' => code, 'message' => message }
        })
      end

      # Convenience: send a JSON-RPC notification (no id)
      sig { params(method_name: String, params: T.untyped).void }
      def send_notification(method_name, params)
        write_message({ 'jsonrpc' => '2.0', 'method' => method_name, 'params' => params })
      end

      # Convenience: send a JSON-RPC request
      sig { params(id: T.untyped, method_name: String, params: T.untyped).void }
      def send_request(id, method_name, params)
        write_message({ 'jsonrpc' => '2.0', 'id' => id, 'method' => method_name, 'params' => params })
      end
    end
  end
end
