# typed: true
# frozen_string_literal: true

return unless defined?(Tapioca::Dsl::Compiler)

require 'set'

module Tapioca
  module Dsl
    module Compilers
      class SorbetView < Compiler
        extend T::Sig

        ConstantType = type_member { { fixed: T.class_of(::SorbetView) } }

        class << self
          extend T::Sig

          sig { override.returns(T::Enumerable[Module]) }
          def gather_constants
            [::SorbetView]
          end
        end

        sig { override.void }
        def decorate
          @module_cache = T.let({}, T::Hash[String, RBI::Scope])

          controllers = ObjectSpace.each_object(Class).select do |klass|
            klass < ::ActionController::Base && !klass.abstract?
          rescue StandardError
            false
          end

          controllers.each do |controller|
            process_controller(controller)
          end
        end

        private

        sig { params(controller: T.untyped).void }
        def process_controller(controller)
          actions = controller.action_methods.to_a

          actions.each do |action_name|
            next unless valid_identifier?(action_name)

            ivars = extract_instance_variables(controller, action_name)
            next if ivars.empty?

            path = controller.controller_path
            parts = path.split('/').map { |p| camelize(p) }
            action_class = camelize(action_name)

            # 1) module SorbetView::Ivars::<path>::<action> with attr_reader
            ivar_module_name = "SorbetView::Ivars::#{parts.join('::')}::#{action_class}"
            create_module_from_path(ivar_module_name) do |mod|
              ivars.each do |ivar|
                name = ivar.delete_prefix('@')
                sig = RBI::Sig.new(return_type: 'T.untyped')
                mod << RBI::AttrReader.new(name.to_sym, sigs: [sig])
              end
            end

            # 2) class SorbetView::Generated::<path>::<action> includes the ivar module
            class_name = "SorbetView::Generated::#{parts.join('::')}::#{action_class}"
            create_class_from_path(class_name) do |klass|
              klass.create_include(ivar_module_name)
            end
          end
        end

        sig { params(name: String).returns(T::Boolean) }
        def valid_identifier?(name)
          name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
        end

        sig { params(str: String).returns(String) }
        def camelize(str)
          str.split('_').map(&:capitalize).join
        end

        sig { params(controller: T.untyped, action_name: String).returns(T::Array[String]) }
        def extract_instance_variables(controller, action_name)
          method_obj = controller.instance_method(action_name)
          source_location = method_obj.source_location
          return [] unless source_location

          file, start_line = source_location
          return [] unless file && File.exist?(file)

          lines = File.readlines(file)
          ivars = T.let(Set.new, T::Set[String])
          depth = 0
          started = false

          lines[(start_line - 1)..].each do |line|
            stripped = line.strip

            unless started
              started = true
              next
            end

            next if stripped.start_with?('#')

            depth += 1 if stripped.match?(/\b(def|class|module|begin)\b/) ||
                          stripped.match?(/\bdo\s*(\|.*\|)?\s*$/)
            depth -= 1 if stripped == 'end' || stripped.start_with?('end ')

            break if depth < 0

            line.scan(/@([a-z_]\w*)\s*[|&]?=/).each do |match|
              name = "@#{match[0]}"
              ivars.add(name) unless name.start_with?('@_')
            end
          end

          ivars.to_a.sort
        rescue NameError, TypeError
          []
        end

        sig { params(class_name: String, block: T.proc.params(klass: T.untyped).void).void }
        def create_class_from_path(class_name, &block)
          parts = class_name.split('::')
          current = resolve_module_path(parts[0..-2])
          current.create_class(T.must(parts.last), &block)
        end

        sig { params(module_name: String, block: T.proc.params(mod: T.untyped).void).void }
        def create_module_from_path(module_name, &block)
          parts = module_name.split('::')
          current = resolve_module_path(parts[0..-2])
          mod = current.create_module(T.must(parts.last))
          block.call(mod)
        end

        sig { params(parts: T::Array[String]).returns(RBI::Scope) }
        def resolve_module_path(parts)
          current = root
          path_so_far = +''

          parts.each do |part|
            path_so_far = path_so_far.empty? ? part : "#{path_so_far}::#{part}"
            if T.must(@module_cache).key?(path_so_far)
              current = T.must(T.must(@module_cache)[path_so_far])
            else
              current = current.create_module(part)
              T.must(@module_cache)[path_so_far] = current
            end
          end

          current
        end
      end
    end
  end
end
