# typed: strict
# frozen_string_literal: true

module SorbetView
  module Perf
    extend T::Sig

    class Metric < T::Struct
      prop :count, Integer, default: 0
      prop :total_ms, Float, default: 0.0
      prop :min_ms, Float, default: Float::INFINITY
      prop :max_ms, Float, default: 0.0
    end

    @metrics = T.let({}, T::Hash[String, Metric])
    @enabled = T.let(true, T::Boolean)

    class << self
      extend T::Sig

      sig { returns(T::Boolean) }
      attr_accessor :enabled

      sig { returns(T::Hash[String, Metric]) }
      attr_reader :metrics

      sig do
        type_parameters(:R)
          .params(label: String, blk: T.proc.returns(T.type_parameter(:R)))
          .returns(T.type_parameter(:R))
      end
      def measure(label, &blk)
        unless @enabled
          return yield
        end

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0

        metric = @metrics[label] ||= Metric.new
        metric.count += 1
        metric.total_ms += elapsed_ms
        metric.min_ms = elapsed_ms if elapsed_ms < metric.min_ms
        metric.max_ms = elapsed_ms if elapsed_ms > metric.max_ms

        result
      end

      sig { void }
      def reset!
        @metrics = {}
      end

      sig { params(io: IO).void }
      def report(io: $stderr)
        return if @metrics.empty?

        io.puts "\n=== SorbetView Performance Report ==="
        io.puts format('%-35s %8s %10s %10s %10s %10s', 'Label', 'Count', 'Total(ms)', 'Avg(ms)', 'Min(ms)', 'Max(ms)')
        io.puts '-' * 90

        @metrics.sort_by { |_, m| -m.total_ms }.each do |label, m|
          avg = m.count > 0 ? m.total_ms / m.count : 0.0
          min_val = m.min_ms == Float::INFINITY ? 0.0 : m.min_ms
          io.puts format('%-35s %8d %10.2f %10.2f %10.2f %10.2f', label, m.count, m.total_ms, avg, min_val, m.max_ms)
        end

        io.puts '=' * 90
        io.puts ''
      end

      sig { params(logger: Logger).void }
      def report_to_logger(logger)
        return if @metrics.empty?

        lines = ["\n=== SorbetView Performance Report ==="]
        lines << format('%-35s %8s %10s %10s %10s %10s', 'Label', 'Count', 'Total(ms)', 'Avg(ms)', 'Min(ms)', 'Max(ms)')
        lines << '-' * 90

        @metrics.sort_by { |_, m| -m.total_ms }.each do |label, m|
          avg = m.count > 0 ? m.total_ms / m.count : 0.0
          min_val = m.min_ms == Float::INFINITY ? 0.0 : m.min_ms
          lines << format('%-35s %8d %10.2f %10.2f %10.2f %10.2f', label, m.count, m.total_ms, avg, min_val, m.max_ms)
        end

        lines << '=' * 90
        logger.info(lines.join("\n"))
      end
    end
  end
end
