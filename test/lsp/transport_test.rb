# typed: true
# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class TransportTest < Minitest::Test
  def test_write_and_read_message
    pipe_r, pipe_w = IO.pipe

    writer = SorbetView::Lsp::Transport.new(input: StringIO.new, output: pipe_w)
    reader = SorbetView::Lsp::Transport.new(input: pipe_r, output: StringIO.new)

    message = { 'jsonrpc' => '2.0', 'method' => 'test', 'params' => { 'foo' => 'bar' } }
    writer.write_message(message)
    pipe_w.close

    received = reader.read_message
    assert_equal message, received
  end

  def test_read_returns_nil_on_eof
    reader = SorbetView::Lsp::Transport.new(input: StringIO.new(''), output: StringIO.new)
    assert_nil reader.read_message
  end

  def test_send_response
    output = StringIO.new
    transport = SorbetView::Lsp::Transport.new(input: StringIO.new, output: output)

    transport.send_response(1, { 'value' => 42 })
    output.rewind
    raw = output.read

    assert_includes raw, 'Content-Length:'
    assert_includes raw, '"id":1'
    assert_includes raw, '"result"'
  end

  def test_send_notification
    output = StringIO.new
    transport = SorbetView::Lsp::Transport.new(input: StringIO.new, output: output)

    transport.send_notification('textDocument/publishDiagnostics', { 'uri' => 'file:///test' })
    output.rewind
    raw = output.read

    assert_includes raw, '"method":"textDocument/publishDiagnostics"'
    refute_includes raw, '"id"'
  end

  def test_send_error
    output = StringIO.new
    transport = SorbetView::Lsp::Transport.new(input: StringIO.new, output: output)

    transport.send_error(5, -32600, 'Invalid Request')
    output.rewind
    raw = output.read

    assert_includes raw, '"id":5'
    assert_includes raw, '"error"'
    assert_includes raw, 'Invalid Request'
  end

  def test_roundtrip_multiple_messages
    pipe_r, pipe_w = IO.pipe

    writer = SorbetView::Lsp::Transport.new(input: StringIO.new, output: pipe_w)
    reader = SorbetView::Lsp::Transport.new(input: pipe_r, output: StringIO.new)

    messages = [
      { 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'initialize', 'params' => {} },
      { 'jsonrpc' => '2.0', 'method' => 'initialized', 'params' => {} },
      { 'jsonrpc' => '2.0', 'id' => 2, 'method' => 'shutdown' }
    ]

    messages.each { |m| writer.write_message(m) }
    pipe_w.close

    received = []
    loop do
      msg = reader.read_message
      break if msg.nil?

      received << msg
    end

    assert_equal messages.length, received.length
    assert_equal 'initialize', received[0]['method']
    assert_equal 'initialized', received[1]['method']
    assert_equal 'shutdown', received[2]['method']
  end
end
