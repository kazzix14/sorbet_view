# typed: strict
# frozen_string_literal: true

module SorbetView
  module Compiler
    class ComponentCompiler
      extend T::Sig

      sig { params(adapter: ParserAdapter, config: Configuration).void }
      def initialize(adapter: Adapters::ErbAdapter.new, config: Configuration.load)
        @adapter = adapter
        @generator = T.let(RubyGenerator.new, RubyGenerator)
        @config = config
      end

      sig { params(path: String, source: String).returns(T::Array[CompileResult]) }
      def compile(path, source)
        extractions = HeredocExtractor.extract(source, path)
        extractions.map do |extraction|
          segments = @adapter.extract_segments(extraction.erb_source)

          # Add line_offset/column_offset so source map points to correct positions in the .rb file
          adjusted = segments.map do |seg|
            RubySegment.new(
              code: seg.code,
              line: seg.line + extraction.line_offset,
              column: seg.column + extraction.column_offset,
              type: seg.type
            )
          end

          context = TemplateContext.resolve_component(
            extraction.component_path,
            extraction.class_name,
            @config
          )
          @generator.generate(segments: adjusted, context: context, config: @config, component_mode: true)
        end
      end

      sig { params(path: String).returns(T::Array[CompileResult]) }
      def compile_file(path)
        source = File.read(path)
        compile(path, source)
      end
    end
  end
end
