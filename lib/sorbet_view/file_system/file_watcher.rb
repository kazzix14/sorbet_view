# typed: strict
# frozen_string_literal: true

require 'listen'

module SorbetView
  module FileSystem
    class FileWatcher
      extend T::Sig

      sig do
        params(
          config: Configuration,
          on_change: T.proc.params(modified: T::Array[String], added: T::Array[String], removed: T::Array[String]).void
        ).void
      end
      def initialize(config:, &on_change)
        @config = config
        @on_change = on_change
        @listener = T.let(nil, T.untyped)
      end

      sig { void }
      def start
        dirs = @config.input_dirs.select { |d| Dir.exist?(d) }
        return if dirs.empty?

        @listener = Listen.to(
          *dirs,
          only: /\.erb$/,
          wait_for_delay: 0.1
        ) do |modified, added, removed|
          # Filter out excluded paths
          modified = filter_paths(modified)
          added = filter_paths(added)
          removed = filter_paths(removed)

          next if modified.empty? && added.empty? && removed.empty?

          @on_change.call(modified, added, removed)
        end

        @listener.start
      end

      sig { void }
      def stop
        @listener&.stop
      end

      private

      sig { params(paths: T::Array[String]).returns(T::Array[String]) }
      def filter_paths(paths)
        paths.reject do |path|
          @config.exclude_paths.any? { |ex| path.include?(ex) }
        end
      end
    end
  end
end
