# typed: strict
# frozen_string_literal: true

module SorbetView
  module FileSystem
    class ProjectScanner
      extend T::Sig

      sig { params(config: Configuration).returns(T::Array[String]) }
      def self.scan(config)
        Perf.measure('scanner.scan_templates') do
          config.input_dirs.flat_map do |dir|
            Dir.glob(File.join(dir, '**', '*.erb'))
          end.reject do |path|
            config.exclude_paths.any? { |ex| path.start_with?(ex) }
          end.sort
        end
      end

      sig { params(config: Configuration).returns(T::Array[String]) }
      def self.scan_components(config)
        Perf.measure('scanner.scan_components') do
          config.component_dirs.flat_map do |dir|
            Dir.glob(File.join(dir, '**', '*.rb'))
          end.reject do |path|
            config.exclude_paths.any? { |ex| path.start_with?(ex) }
          end.select do |path|
            File.read(path).include?('erb_template')
          end.sort
        end
      end
    end
  end
end
