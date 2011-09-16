module EventState
  #
  # Base class for state machines driven by +EventMachine+.
  #
  # This class provides a domain-specific language (DSL) for declaring the
  # structure of the machine. The language is defined in {MachineDSL}. See the
  # {file:README} for examples and the general idea of how this works.
  #
  # If you are sending ruby objects as messages, see {ObjectMachine}; it handles
  # serialization (using EventMachine's +ObjectProtocol+) and names messages
  # according to their classes (but you can easily override this).
  #
  # If you have some other kind of messages, then you should subclass this class
  # directly. Three methods are required:
  # 1. Override EventMachine's +receive_data+ method to call
  #    {#transition_on_recv} with the received message.
  # 2. Override EventMachine's +send_data+ method to call {#transition_on_send}
  #    with the message to be sent.
  # 3. Override {#message_name}. This takes a message to be sent or received and
  #    determines its name, which relates the message to the declared protocol.
  #
  class MachineBase < EventMachine::Connection

    # include the DSL methods in the metaclass
    # the parentheses are here to avoid confusing yard; without them, it
    # reports the DSL methods as instance methods for this class (20110915) 
    (class << self; include MachineDSL; end)

    #
    # Called by +EventMachine+ when a new connection has been established. This
    # calls the +on_enter+ handler for the machine's start state with a +nil+
    # message.
    #
    # Be sure to call +super+ if you override this method, or the +on_enter+
    # handler for the start state will not be called.
    #
    # @return [nil]
    #
    def post_init
      @state = self.class.start_state
      @state.call_on_enter self, nil, nil
      nil
    end

    #
    # Get the name of a message; this method maps the data sent or received by
    # the machine to the message names used to define the transitions (using
    # {MachineDSL#on_send} on {MachineDSL#on_recv}).
    #
    # The requirements are that a message name must be hashable and comparable
    # by value. For example, a symbol, string, number or class makes a good
    # message name; so does a ruby Struct.
    #
    # @param [Object] message to be sent
    #
    # @return [Object] message name
    #
    # @abstract
    #
    def message_name message
      raise NotImplementedError
    end

    #
    # Move the state machine from its current state to the successor state that
    # it should be in after receiving the given +message+, according to the
    # protocol defined using the DSL.
    #
    # If the received message is not valid according to the protocol, then the
    # protocol error handler is called (see {MachineDSL#on_protocol_error}). 
    #
    # The precise order of events is:
    # 1. the +on_exit+ handler of the current state is called with +message+ 
    # 2. the current state is set to the successor state
    # 3. the +on_enter+ handler of the new current state is called with
    #    +message+
    #
    # @param [Object] message received
    #
    # @return [nil]
    #
    def transition_on_recv message
      msg_name = message_name(message)
      puts "#{self.class}: RECV #{msg_name} #{message.inspect}"
      # look up successor state
      next_state_name = @state.on_recvs[msg_name]

      # if there is no registered successor state, it's a protocol error
      if next_state_name.nil?
        self.class.on_protocol_error.call(message)
      else
        transition msg_name, message, next_state_name
      end

      nil
    end

    #
    # Move the state machine from its current state to the successor state that
    # it should be in after sending the given +message+, according to the
    # protocol defined using the DSL.
    #
    # If the message to be sent is not valid according to the protocol, then the
    # protocol error handler is called (see {MachineDSL#on_protocol_error}). If
    # the message is valid, then the precise order of events is:
    # 1. this method yields the message to the supplied block (if any); the
    #    intention is that the block is used to actually send the message
    # 2. the +on_exit+ handler of the current state is called with +message+ 
    # 3. the current state is set to the successor state
    # 4. the +on_enter+ handler of the new current state is called with
    #    +message+
    #
    # @param [Object] message received
    #
    # @yield [message] should actually send the message, typically using
    #        EventMachine's +send_data+ method
    #
    # @yieldparam [Object] message the same message passed to this method
    #
    # @return [nil]
    #
    def transition_on_send message
      msg_name = message_name(message)
      puts "#{self.class}: SEND #{msg_name} #{message.inspect}"
      # look up successor state
      next_state_name = @state.on_sends[msg_name]

      # if there is no registered successor state, it's a protocol error
      if next_state_name.nil?
        self.class.on_protocol_error.call(message)
      else
        # let the caller send the message before we transition
        yield message if block_given?
        
        transition msg_name, message, next_state_name
      end

      nil
    end

    private
    
    #
    # Update @state and call appropriate on_exit and on_enter handlers.
    #
    def transition message_name, message, next_state_name
      @state.call_on_exit  self, message_name, message
      @state = self.class.states[next_state_name]
      @state.call_on_enter self, message_name, message
    end
  end
end

