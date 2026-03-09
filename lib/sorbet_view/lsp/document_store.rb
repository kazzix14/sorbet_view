# typed: strict
# frozen_string_literal: true

module SorbetView
  module Lsp
    class Document < T::Struct
      const :uri, String
      prop :content, String
      prop :version, Integer
      prop :compile_result, T.nilable(Compiler::CompileResult)
    end

    # In-memory store of open template documents
    class DocumentStore
      extend T::Sig

      sig { void }
      def initialize
        @documents = T.let({}, T::Hash[String, Document])
      end

      sig { params(uri: String, content: String, version: Integer).returns(Document) }
      def open(uri, content, version)
        doc = Document.new(uri: uri, content: content, version: version, compile_result: nil)
        @documents[uri] = doc
        doc
      end

      sig { params(uri: String, content: String, version: Integer).returns(T.nilable(Document)) }
      def change(uri, content, version)
        doc = @documents[uri]
        return nil unless doc

        doc.content = content
        doc.version = version
        doc.compile_result = nil # Invalidate
        doc
      end

      sig { params(uri: String).void }
      def close(uri)
        @documents.delete(uri)
      end

      sig { params(uri: String).returns(T.nilable(Document)) }
      def get(uri)
        @documents[uri]
      end

      sig { returns(T::Array[Document]) }
      def all
        @documents.values
      end
    end
  end
end
