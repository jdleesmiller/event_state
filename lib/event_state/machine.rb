require 'event_state/machine_dsl'

module EventState

  #
  # Base class for a state machine that is driven by +EventMachine+. The machine
  # is configured using a domain-specific language defined in {MachineDSL}.  See
  # the {file:README} for examples and more information.
  #
  class Machine < EventMachine::Connection
    include EventMachine::P::ObjectProtocol

    # include the DSL methods in the metaclass
    # the parentheses are here to avoid confusing yard; without them, it
    # reports the DSL methods as instance methods in this class (20110915) 
    (class << self; include MachineDSL; end)

    #
    # Constructor.
    #
    def initialize(*)
      super

      # put machine into the start state
      @state = self.class.start_state
    end

    #
    # Called by +EventMachine+ when a new connection has been established. This
    # calls the +on_enter+ handler for the machine's start state with a +nil+
    # message.
    #
    # Be sure to call +super+ if you override this method, or +on_enter+ handler
    # for the start state will not be called.
    #
    # @return [nil]
    #
    def post_init
      puts "MACHINE POST_INIT: #{@state.name}"

      begin
        @state.call_on_enter self, nil, nil
      rescue
        p $!
        puts $!.backtrace
        raise
      end
      nil
    end

    #
    # Called by +EventMachine+ (actually, the +ObjectProtocol+) when a message
    # is received.
    #
    # Note: if you want to receive non-messages as well, you should override
    # this method in your subclass, and call +super+ only when a message is
    # received.
    #
    # The precise order of events is:
    # 1. the +on_exit+ handler of the current state is called with +message+ 
    # 2. the current state is set to the successor state
    # 3. the +on_enter+ handler of the new current state is called with
    #    +message+
    #
    # @return [nil]
    #
    def receive_object message
      puts "MACHINE RECV: #{message.inspect} (#{message.to_sym})"

      # all valid messages must have a symbolic name
      raise "received object is not a message: #{message.inspect}" unless
        message.respond_to?(:to_sym)

      # see what our next state is
      message_name = message.to_sym
      next_state_name = @state.on_recvs[message_name]

      # if there is no next state, it's a protocol error
      if next_state_name.nil?
        self.class.on_protocol_error.call(message)
      else
        transition message_name, message, next_state_name
      end

      nil
    end

    #
    # Send the given message to the client and update the current machine state.
    #
    # The precise order of events is:
    # 1. the +message+ is sent using <tt>ObjectProtocol</tt>'s +send_object+
    # 2. the +on_exit+ handler of the current state is called with +message+ 
    # 3. the current state is set to the successor state
    # 4. the +on_enter+ handler of the new current state is called with
    #    +message+
    #
    # @param [Message] message to be sent; it must respond to +to_sym+, which
    #        must return a valid message name for the machine
    #
    # @return [nil]
    #
    def send_message message
      puts "MACHINE SEND: #{message.inspect}"

      # all valid messages must have a symbolic name
      raise "object to be sent is not a message: #{message.inspect}" unless
        message.respond_to?(:to_sym)

      # see what our next state is
      message_name = message.to_sym
      next_state_name = @state.on_sends[message_name]

      # if there is no next state, it's a protocol error
      if next_state_name.nil?
        self.class.on_protocol_error.call(message)
      else
        send_object message

        transition message_name, message, next_state_name
      end

      nil
    end

    #
    # The name of the machine's current state.
    #
    # @return [Symbol]
    #
    def state_name
      @state.name
    end

    private

    #
    # Update current state based on the message that was sent or received.
    #
    def transition message_name, message, next_state_name
      @state.call_on_exit  self, message_name, message
      @state = self.class.states[next_state_name]
      @state.call_on_enter self, message_name, message
    end
  end
end

