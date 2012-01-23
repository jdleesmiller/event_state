#require 'simplecov'
#SimpleCov.start

require 'event_state'
require 'test/unit'

# load example machines
require 'event_state/ex_echo'
require 'event_state/ex_readme'
require 'event_state/ex_secret'
require 'event_state/ex_job'

# give more helpful errors
Thread.abort_on_exception = true

class TestEventState < Test::Unit::TestCase
  include EventState

  DEFAULT_HOST = 'localhost'
  DEFAULT_PORT = 14159

  #
  # Run server and client in the same EventMachine reactor. Returns the client.
  #
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
      EventMachine.start_server(host, port, server_class, *server_args)
      client = EventMachine.connect(host, port, client_class,
                                    *client_args, &block)
    end
    client
  end

  #
  # Spawn the given server in a new process (fork) and yield once it's up and
  # running.
  #
  # This works by spawning a child process and starting an EventMachine reactor
  # in the child process. You should start a new one in the given block, if you
  # want to connect a client.
  #
  def with_forked_server server_class, server_args=[], opts={}, &block
    host = opts[:host] || DEFAULT_HOST
    port = opts[:port] || DEFAULT_PORT

    # use a pipe to signal the parent that the child server has started
    p_r, p_w = IO.pipe
    child_pid = fork do
      p_r.close
      EventMachine.run do
        EventMachine.start_server(host, port, server_class, *server_args)
        p_w.puts
        p_w.close
      end
    end
    p_w.close
    p_r.gets # wait for child process to start server
    p_r.close

    begin
      yield host, port
    ensure
      Process.kill 'TERM', child_pid
      Process.wait
    end
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

  def test_delayed_echo
    assert_equal %w(foo bar baz), 
      run_server_and_client(DelayedEchoServer, EchoClient,
        server_args: [0.5],
        client_args: [%w(foo bar baz), []]).recorder
  end

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

  def test_dsl_no_nested_protocols
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

  class TestDSLImplicitState < EventState::Machine; end

  def test_dsl_implicit_state
    #
    # if a state is referenced in an on_send or on_recv but is not declared with
    # state, the protocol method should add it to @states when it terminates
    #
    inner_states = nil
    outer_states = nil
    TestDSLImplicitState.class_eval do
      protocol do
        state :foo do
          on_send :bar, :baz
        end
        inner_states = states.dup
      end
      outer_states = states.dup
    end
    assert_nil inner_states[:baz]
    assert_kind_of EventState::State, outer_states[:baz]
  end

  class TestDelayClient < EventState::ObjectMachine
    def initialize log, delays
      super
      @log = log
      @delays = delays
    end

    protocol do
      state :foo do
        on_send String, :bar
        on_enter do
          EM.defer proc {
            @log << "sleeping in foo"
            sleep @delays.shift
            @log << "finished sleep in foo"
          }, proc {
            send_message 'awake!'
          }
        end
        on_unbind do
          @log << "unbound in foo"
        end
      end

      state :bar do
        on_enter do
          EM.defer proc {
            @log << "sleeping in bar"
            sleep @delays.shift
            @log << "finished sleep in bar"
          }, proc {
            close_connection
          }
        end
        on_unbind do
          @log << "unbound in bar"
        end
      end
    end
  end

  class TestUnbindServer < EventState::ObjectMachine
    def initialize log, timeout
      super
      @log = log
      @timeout = timeout
    end
    protocol do
      state :foo do
        on_enter do
          @log << "entered foo"
          self.comm_inactivity_timeout = @timeout
        end
        on_unbind do
          @log << "unbound in foo"
          EM.stop
        end

        on_recv String, :bar
      end
      state :bar do
        on_enter do
          @log << "entered bar"
        end
        on_unbind do
          @log << "unbound in bar"
          EM.stop
        end
      end
    end
  end

  def test_unbind_on_timeout
    #
    # first, set delays so that we time out in the first server state (foo)
    # 
    server_log = []
    client_log = []
    run_server_and_client(TestUnbindServer, TestDelayClient,
                          server_args: [server_log,  1],
                          client_args: [client_log, [2,2]])
    assert_equal [
      "entered foo",
      "unbound in foo"], server_log

    # the client log isn't entirely deterministic; depends on threading
    assert_equal "sleeping in foo", client_log.first

    #
    # next, set delays so that we time out in the second server state (bar)
    #
    server_log = []
    client_log = []
    run_server_and_client(TestUnbindServer, TestDelayClient,
                          server_args: [server_log,  1],
                          client_args: [client_log, [0.5,2]])
    assert_equal [
      "entered foo",
      "entered bar",
      "unbound in bar"], server_log
    assert_equal [
      "sleeping in foo",
      "finished sleep in foo",
      "sleeping in bar",
      "unbound in bar"], client_log
  end

  def test_readme_example
    MessageEchoClient.demo
  end

  class TestProtocolErrorSend < EventState::ObjectMachine
    protocol do
      state :foo do
        on_send String, :bar
        on_enter do
          send_message 42
        end
      end
    end
  end

  def test_protocol_error_on_send
    #
    # TestProtocolErrorSend sends an integer instead of a string; this should
    # cause an error on the server side; the server doesn't shut down; it just
    # calls the EM error_handler
    #
    error = nil
    EM.run do
      EM.error_handler do |e|
        # we get a ConnectionNotBound error from the client, too
        error = e if !error
        EM.stop
      end
      EM.start_server DEFAULT_HOST, DEFAULT_PORT, TestProtocolErrorSend 
      EM.connect DEFAULT_HOST, DEFAULT_PORT do
        # just want to force the server to init
      end
    end

    assert_kind_of SendProtocolError, error
    assert_kind_of TestProtocolErrorSend, error.machine
    assert_equal   :foo, error.state_name
    assert_equal   :send, error.action
    assert_equal   Fixnum, error.message_name
    assert_equal   42, error.data
  end

  class TestProtocolErrorClient < EventState::ObjectMachine
    protocol do
      state :foo do
        on_send Fixnum, :bar
        on_enter do
          send_message 42
        end
      end
    end
  end

  def test_protocol_error_on_recv
    #
    # the EchoServer expects a String, but TestProtocolErrorClient gives it an
    # integer; this causes a protocol error
    #
    error = nil
    EM.run do
      EM.error_handler do |e|
        error = e
        EM.stop
      end
      EM.start_server DEFAULT_HOST, DEFAULT_PORT, EchoServer 
      EM.connect DEFAULT_HOST, DEFAULT_PORT, TestProtocolErrorClient
    end

    assert_kind_of RecvProtocolError, error
    assert_kind_of EchoServer, error.machine
    assert_equal   :listening, error.state_name
    assert_equal   :recv, error.action
    assert_equal   Fixnum, error.message_name
    assert_equal   42, error.data
  end

  def test_job_server_timeouts
    client_logs = [[],[],[],[]]
    with_forked_server JobServer do |host, port|
      EM.run do
        EM.add_timer 0.1 do
          EventMachine.connect(host, port, JobClient, 0.1, 1.0, client_logs[0])
        end
        EM.add_timer 0.5 do
          EventMachine.connect(host, port, JobClient, 0.1, 1.0, client_logs[1])
        end
        EM.add_timer 1.5 do
          EventMachine.connect(host, port, JobClient, 0.1, 2.5, client_logs[2])
        end
        EM.add_timer 4.5 do
          EventMachine.connect(host, port, JobClient, 1.5, 0.5, client_logs[3])
        end
        EM.add_timer 7 do
          EM.stop
        end
      end
    end

    # first client gets its job processed
    assert_equal [
      'starting',
      'entering sending state',
      'sending job',
      'closed: work: 1.0'], client_logs[0]

    # second client tries while job is still being processed
    assert_equal [
      'starting',
      'busy'], client_logs[1]

    # third client's job time gets sent but times out
    assert_equal [
      'starting',
      'entering sending state',
      'sending job',
      'timed out in waiting state',
      'unbind in waiting state'], client_logs[2]

    # fourth client waits too long to send the job; server gives up
    assert_equal [
      'starting',
      'entering sending state',
      'unbind in sending state'], client_logs[3]
  end
end

