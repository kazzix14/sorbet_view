# typed: strict
# frozen_string_literal: true

module SorbetView
  module Compiler
    class TemplateContext < T::Struct
      const :class_name, String
      const :superclass, T.nilable(String)
      const :includes, T::Array[String]
      const :template_path, String
      const :ruby_path, String

      extend T::Sig

      sig { returns(String) }
      def superclass_clause
        superclass ? " < #{superclass}" : ''
      end

      sig { params(component_path: String, class_name: String, config: Configuration).returns(TemplateContext) }
      def self.resolve_component(component_path, class_name, config)
        ruby_path = File.join(config.output_dir, "#{component_path}__erb_template.rb")
        new(
          class_name: class_name,
          superclass: nil,
          includes: [],
          template_path: component_path,
          ruby_path: ruby_path
        )
      end

      sig { params(template_path: String, config: Configuration).returns(TemplateContext) }
      def self.resolve(template_path, config)
        ruby_path = File.join(config.output_dir, "#{template_path}.rb")
        classification = classify(template_path, config)

        case classification
        when :mailer_view
          resolve_mailer_view(template_path, ruby_path, config)
        when :layout
          resolve_layout(template_path, ruby_path, config)
        when :partial
          resolve_partial(template_path, ruby_path, config)
        when :controller_view
          resolve_controller_view(template_path, ruby_path, config)
        else
          resolve_generic(template_path, ruby_path, config)
        end
      end

      class << self
        extend T::Sig

        private

        # Strip the matching input_dir prefix from a template path
        # "app/views/users/show.html.erb" → "users/show.html.erb"
        # "app/users/show.html.erb" (input_dirs: ['app/']) → "users/show.html.erb"
        sig { params(path: String, config: Configuration).returns(String) }
        def strip_input_dir(path, config)
          config.input_dirs.each do |dir|
            prefix = dir.end_with?('/') ? dir : "#{dir}/"
            if path.start_with?(prefix)
              relative = path.delete_prefix(prefix)
              # Also strip "views/" if the input_dir didn't include it
              # e.g. input_dirs: ['app/'] with path 'app/views/users/show.html.erb'
              relative = relative.delete_prefix('views/') if relative.start_with?('views/')
              return relative
            end
          end
          path
        end

        sig { params(path: String, config: Configuration).returns(Symbol) }
        def classify(path, config)
          basename = File.basename(path)
          relative = strip_input_dir(path, config)

          if path.include?('_mailer/') || path.include?('mailers/')
            :mailer_view
          elsif relative.start_with?('layouts/')
            :layout
          elsif basename.start_with?('_')
            :partial
          elsif relative != path
            # input_dir prefix was stripped → this is a view under input_dirs
            :controller_view
          else
            :generic
          end
        end

        sig { params(path: String, config: Configuration).returns(String) }
        def path_to_class_name(path, config)
          relative = strip_input_dir(path, config)
          filename = File.basename(relative)
          filename_parts = filename.split('.')

          basename = T.must(filename_parts.first)
          basename = basename.delete_prefix('_') # strip partial prefix

          # With 3+ parts (e.g. show.html.erb → [show, html, erb]), the last is the
          # template handler and the middle parts are format/variant extensions.
          # Nest them as sub-classes so show.html.erb and show.turbo_stream.erb
          # don't collide as the same class name.
          format_parts = filename_parts.length >= 3 ? T.must(filename_parts[1..-2]) : []

          dir = File.dirname(relative)

          parts = if dir == '.'
            [basename]
          else
            dir.split('/') + [basename]
          end

          parts += format_parts

          parts.map { |p| camelize(p) }.join('::')
        end

        sig { params(str: String).returns(String) }
        def camelize(str)
          str.split(/[_\-]/).map(&:capitalize).join
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_controller_view(path, ruby_path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path, config)}",
            superclass: '::ActionView::Base',
            includes: [
              '::ApplicationController::HelperMethods',
              *config.extra_includes
            ],
            template_path: path,
            ruby_path: ruby_path
          )
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_mailer_view(path, ruby_path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path, config)}",
            superclass: '::ActionView::Base',
            includes: [
              '::ActionMailer::Base',
              *config.extra_includes
            ],
            template_path: path,
            ruby_path: ruby_path
          )
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_layout(path, ruby_path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path, config)}",
            superclass: '::ActionView::Base',
            includes: [
              '::ApplicationController::HelperMethods',
              *config.extra_includes
            ],
            template_path: path,
            ruby_path: ruby_path
          )
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_partial(path, ruby_path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path, config)}",
            superclass: '::ActionView::Base',
            includes: [
              '::ApplicationController::HelperMethods',
              *config.extra_includes
            ],
            template_path: path,
            ruby_path: ruby_path
          )
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_generic(path, ruby_path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path, config)}",
            superclass: nil,
            includes: config.extra_includes,
            template_path: path,
            ruby_path: ruby_path
          )
        end
      end
    end
  end
end
