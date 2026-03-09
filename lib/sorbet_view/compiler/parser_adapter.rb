# typed: strict
# frozen_string_literal: true

module SorbetView
  module Compiler
    module ParserAdapter
      extend T::Sig
      extend T::Helpers

      interface!

      sig { abstract.params(source: String).returns(T::Array[RubySegment]) }
      def extract_segments(source); end
    end
  end
end
