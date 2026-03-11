# typed: strict
# frozen_string_literal: true

module SorbetView
  module Compiler
    class TemplateCompiler
      extend T::Sig

      sig { params(adapter: ParserAdapter, config: Configuration).void }
      def initialize(adapter: Adapters::ErbAdapter.new, config: Configuration.load)
        @adapter = adapter
        @generator = T.let(RubyGenerator.new, RubyGenerator)
        @config = config
      end

      sig { params(template_path: String, source: String).returns(CompileResult) }
      def compile(template_path, source)
        Perf.measure('compiler.compile') do
          segments = @adapter.extract_segments(source)
          context = TemplateContext.resolve(template_path, @config)
          @generator.generate(segments: segments, context: context, config: @config)
        end
      rescue => e
        # On parse failure, generate a minimal file so Sorbet doesn't complain about missing files
        context = TemplateContext.resolve(template_path, @config)
        CompileResult.new(
          ruby_source: "# typed: ignore\n# sorbet_view: failed to parse #{template_path}: #{e.message}\n",
          source_map: SourceMap::SourceMap.empty(template_path, context.ruby_path),
          locals: nil,
          locals_sig: nil
        )
      end

      sig { params(template_path: String).returns(CompileResult) }
      def compile_file(template_path)
        source = File.read(template_path)
        compile(template_path, source)
      end
    end
  end
end
