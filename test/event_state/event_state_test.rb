require 'event_state'
require 'test/unit'

# load example machines
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
      EM.error_handler do |e|
        puts "EM ERROR: #{e.inspect}"
        puts e.backtrace
      end
      EventMachine.start_server host, port, server_class, *server_args
      client = EventMachine.connect(host, port, client_class,
                                    *client_args, &block)
    end
    client
  end

  def run_echo_test client_class
    server_log = []
    recorder = run_server_and_client(LoggingEchoServer, client_class,
      server_args: [server_log],
      client_args: [%w(foo bar baz), []]).recorder

    assert_equal [
      "entering listening state", # on_enter called on the start state
      "exiting listening state",  # when a message is received
      "speaking foo",             # the first noise
      "exiting speaking state",   # sent echo to client
      "entering listening state", # now listening for next noise
      "exiting listening state",  # ...
      "speaking bar",
      "exiting speaking state",
      "entering listening state",
      "exiting listening state",
      "speaking baz",
      "exiting speaking state",
      "entering listening state"], server_log
  end
  
  def test_echo_basic
    assert_equal %w(foo bar baz), 
      run_server_and_client(EchoServer, EchoClient,
        client_args: [%w(foo bar baz), []]).recorder
  end

#  def test_delayed_echo
#    assert_equal %w(foo bar baz), 
#      run_server_and_client(DelayedEchoServer, EchoClient,
#        server_args: [0.5],
#        client_args: [%w(foo bar baz), []]).recorder
#  end

  def test_echo_with_object_protocol_client
    run_echo_test ObjectProtocolEchoClient
  end

  def test_echo_with_event_state_client
    run_echo_test EchoClient
  end

  def test_secret_server
    run_server_and_client(TopSecretServer, TopSecretClient)
  end

  def test_print_state_machine_dot
    dot = EchoClient.print_state_machine_dot(:graph_options => 'rankdir=LR;')
    assert_equal <<DOT, dot.string
digraph "EventState::EchoClient" {
  rankdir=LR;
  speaking [peripheries=2];
  speaking -> listening [color=red,label="String"];
  listening -> speaking [color=blue,label="String"];
}
DOT
  end

  class TestDSLBasic < EventState::Machine; end

  def test_dsl_basic
    #
    # check that we get the transitions right for this simple DSL
    #
    trans = nil
    TestDSLBasic.class_eval do
      protocol do
        state :foo do
          on_recv :hello, :bar
        end
        state :bar do 
          on_recv :good_bye, :foo
        end
      end
      trans = transitions
    end

    assert_equal [
      [:foo, [:recv, :hello], :bar],
      [:bar, [:recv, :good_bye], :foo]], trans
  end

  class TestDSLNoNestedProtocols < EventState::Machine; end

  def test_dsl_no_nested_states
    #
    # nested protocol blocks are illegal
    #
    assert_raises(RuntimeError) {
      TestDSLNoNestedProtocols.class_eval do
        protocol do
          protocol do
          end
        end
      end
    }
  end

  class TestDSLNoNestedStates < EventState::Machine; end

  def test_dsl_no_nested_states
    #
    # nested state blocks are illegal
    #
    assert_raises(RuntimeError) {
      TestDSLNoNestedStates.class_eval do
        protocol do
          state :foo do
            state :bar do
            end
          end
        end
      end
    }
  end
end

