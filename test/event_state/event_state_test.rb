require 'event_state'
require 'test/unit'

require 'event_state/ex_echo'
require 'event_state/ex_secret'

class TestEventState < Test::Unit::TestCase
  include EventState

  DEFAULT_HOST = 'localhost'
  DEFAULT_PORT = 14159

  def run_server_and_client server_class, client_class, opts={}, &block
    host = opts[:host] || DEFAULT_HOST
    port = opts[:port] || DEFAULT_PORT
    server_args = opts[:server_args] || []
    client_args = opts[:client_args] || []

    client = nil
    EM.run do
      EventMachine.start_server host, port, server_class, *server_args
      client = EventMachine.connect(host, port, client_class,
                                    *client_args, &block)
    end
    client
  end

  def run_echo_test client_class
    server_log = []
    recorder = run_server_and_client(EchoServer, client_class,
      server_args: [server_log],
      client_args: [%w(foo bar baz), []]).recorder

    assert_equal [
      "entering listening state", # on_enter called on the start state
      "exiting listening state",  # when a message is received
      "echoing foo",              # the first noise
      "exiting echoing state",    # sent echo to client
      "entering listening state", # now listening for next noise
      "exiting listening state",  # ...
      "echoing bar",
      "exiting echoing state",
      "entering listening state",
      "exiting listening state",
      "echoing baz",
      "exiting echoing state",
      "entering listening state"], server_log

    assert_equal %w(foo bar baz), recorder
  end
  
#  def test_echo_with_object_protocol_client
#    run_echo_test ObjectProtocolEchoClient
#  end
#
#  def test_echo_with_event_state_client
#    run_echo_test EchoClient
#  end

  def test_secret_server
    run_server_and_client(TopSecretServer, TopSecretClient)
  end
end

