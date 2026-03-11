# typed: strict
# frozen_string_literal: true

module SorbetView
  module CLI
    class Runner
      extend T::Sig

      COMMANDS = T.let({
        'tc' => 'Compile templates and run srb tc',
        'compile' => 'Compile templates to Ruby files',
        'lsp' => 'Start LSP proxy server',
        'clean' => 'Remove generated files',
        'init' => 'Generate .sorbet_view.yml config file'
      }.freeze, T::Hash[String, String])

      sig { params(argv: T::Array[String]).void }
      def self.start(argv)
        command = argv[0]
        args = argv[1..] || []

        case command
        when 'tc'
          run_tc(args)
        when 'compile'
          run_compile(args)
        when 'lsp'
          run_lsp(args)
        when 'clean'
          run_clean(args)
        when 'init'
          run_init
        else
          print_usage
        end
      end

      class << self
        extend T::Sig

        private

        # Split args on "--": before is sv args, after is passthrough (e.g. to srb tc)
        sig { params(args: T::Array[String]).returns([T::Array[String], T::Array[String]]) }
        def split_args(args)
          separator = args.index('--')
          if separator
            [args[0...separator], args[(separator + 1)..] || []]
          else
            [args, []]
          end
        end

        sig { params(args: T::Array[String]).returns(Configuration) }
        def parse_config(args)
          sv_args, _ = split_args(args)
          no_config = sv_args.include?('--no-config')
          input_dirs = T.let([], T::Array[String])
          output_dir = T.let(nil, T.nilable(String))

          i = 0
          while i < sv_args.length
            case sv_args[i]
            when '--no-config'
              # handled above
            when '-o', '--output'
              output_dir = sv_args[i + 1]
              i += 1
            when /^-/
              # skip unknown flags
            else
              input_dirs << T.must(sv_args[i])
            end
            i += 1
          end

          base = no_config ? Configuration.new : Configuration.load

          overrides = {}
          overrides['input_dirs'] = input_dirs unless input_dirs.empty?
          overrides['output_dir'] = output_dir if output_dir

          if overrides.empty?
            base
          else
            Configuration.from_hash(base.serialize.merge(overrides))
          end
        end

        sig { params(args: T::Array[String]).void }
        def run_compile(args)
          Perf.reset!
          total_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          config = parse_config(args)
          compiler = Compiler::TemplateCompiler.new(config: config)
          component_compiler = Compiler::ComponentCompiler.new(config: config)
          output_manager = FileSystem::OutputManager.new(config.output_dir)

          templates = FileSystem::ProjectScanner.scan(config)
          puts "Compiling #{templates.length} template(s)..."

          templates.each do |path|
            result = compiler.compile_file(path)

            if result.source_map.entries.empty? && config.skip_missing_locals && requires_locals?(path)
              next
            end

            output_manager.write(result)
            puts "  #{path} -> #{result.source_map.ruby_path}"
          end

          components = FileSystem::ProjectScanner.scan_components(config)
          if components.any?
            puts "Compiling #{components.length} component(s) with erb_template..."

            components.each do |path|
              results = component_compiler.compile_file(path)
              results.each do |result|
                output_manager.write(result)
                puts "  #{path} -> #{result.source_map.ruby_path}"
              end
            end
          end

          total_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - total_start) * 1000.0
          puts "Done. (total: #{total_ms.round(1)}ms)"
          Perf.report
        end

        sig { params(args: T::Array[String]).void }
        def run_tc(args)
          run_compile(args)

          config = parse_config(args)
          _, sorbet_args = split_args(args)
          puts "\nRunning Sorbet..."
          system(config.sorbet_path, 'tc', *sorbet_args)
        end

        sig { params(args: T::Array[String]).void }
        def run_lsp(args)
          _, sorbet_args = split_args(args)
          $stdin.binmode
          $stdout.binmode
          server = Lsp::Server.new(sorbet_args: sorbet_args)
          server.start
        end

        sig { params(args: T::Array[String]).void }
        def run_clean(args)
          config = parse_config(args)
          output_manager = FileSystem::OutputManager.new(config.output_dir)
          output_manager.clean
          puts "Cleaned #{config.output_dir}"
        end

        sig { void }
        def run_init
          if File.exist?(SorbetView::CONFIG_FILE_NAME)
            puts "#{SorbetView::CONFIG_FILE_NAME} already exists"
            return
          end

          File.write(SorbetView::CONFIG_FILE_NAME, <<~YAML)
            # SorbetView configuration
            input_dirs:
              - app/views

            exclude_paths: []

            output_dir: sorbet/templates

            extra_includes: []

            skip_missing_locals: true
          YAML

          puts "Created #{SorbetView::CONFIG_FILE_NAME}"
        end

        sig { void }
        def print_usage
          puts 'Usage: sv <command> [paths...] [options]'
          puts ''
          puts 'Commands:'
          COMMANDS.each do |cmd, desc|
            puts "  #{cmd.ljust(12)} #{desc}"
          end
          puts ''
          puts 'Options:'
          puts '  [paths...]         Input directories (overrides config)'
          puts '  -o, --output DIR   Output directory (overrides config)'
          puts '  --no-config        Ignore .sorbet_view.yml'
          puts '  -- [args...]       Pass remaining args to srb tc (tc/lsp)'
        end

        sig { params(path: String).returns(T::Boolean) }
        def requires_locals?(path)
          basename = File.basename(path)
          basename.start_with?('_') || basename.end_with?('.turbo_stream.erb')
        end
      end
    end
  end
end
