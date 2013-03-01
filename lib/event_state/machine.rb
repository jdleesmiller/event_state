module EventState
  #
  # A class that links the DSL defined in SimpleMachine with a Connection object
  # from EventMachine.
  #
  # If you are sending ruby objects as messages, see {ObjectMachine}; it handles
  # serialization (using EventMachine's +ObjectProtocol+) and names messages
  # according to their classes (but you can override this).
  #
  # If you have some other kind of messages, then you should subclass this class
  # directly. Two methods are required:
  # 1. Override EventMachine's +receive_data+ method to call
  #    {#transition_on_recv} with the received message.
  # 2. Override EventMachine's +send_data+ method to call {#transition_on_send}
  #    with the message to be sent.
  # Note that {#transition_on_recv} and {#transition_on_send} take a message
  # _name_ as well as a message. You have to define the mapping from messages
  # to message names so that the message names correspond with the transitions
  # declared using the DSL ({on_send} and {on_recv} in particular).
  #
  class Machine < EventMachine::Connection

    include SimpleMachine

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
      @state_timer_sigs = []
      add_state_timer @state.timeout, &@state.on_timeout if @state.timeout
      @state.call_on_enter self, nil, nil
      nil
    end

    #
    # Called by +EventMachine+ when a connection is closed. This calls the
    # {on_unbind} handler for the current state and then cancels all state
    # timers. 
    #
    # @return [nil]
    #
    def unbind
      #puts "#{self.class} UNBIND"
      handler = @state.on_unbind
      self.instance_exec(&handler) if handler 
      cancel_state_timers
    end

  end
end

