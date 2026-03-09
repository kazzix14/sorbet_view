# typed: strict
# frozen_string_literal: true

require 'fileutils'
require 'digest'

module SorbetView
  module FileSystem
    class OutputManager
      extend T::Sig

      sig { params(output_dir: String).void }
      def initialize(output_dir)
        @output_dir = output_dir
      end

      sig { params(result: Compiler::CompileResult).void }
      def write(result)
        path = result.source_map.ruby_path
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir)

        # Only write if content changed (avoid unnecessary Watchman triggers)
        if File.exist?(path)
          existing = File.read(path)
          return if existing == result.ruby_source
        end

        File.write(path, result.ruby_source)
      end

      sig { void }
      def clean
        FileUtils.rm_rf(@output_dir)
      end
    end
  end
end
