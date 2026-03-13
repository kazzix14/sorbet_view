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
        Perf.measure('output.write') do
          path = result.source_map.ruby_path
          dir = File.dirname(path)
          FileUtils.mkdir_p(dir)

          # Only write if content changed (avoid unnecessary Watchman triggers)
          if File.exist?(path)
            existing = File.read(path)
            next if existing == result.ruby_source
          end

          File.write(path, result.ruby_source)
        end
      end

      # Delete the compiled output for a given template path
      sig { params(template_path: String).void }
      def delete(template_path)
        ruby_path = File.join(@output_dir, "#{template_path}.rb")
        File.delete(ruby_path) if File.exist?(ruby_path)
      end

      sig { void }
      def clean
        FileUtils.rm_rf(@output_dir)
      end
    end
  end
end
