module EventState

  class HookableMachine

    include SimpleMachine

    attr_accessor :callback

    #
    # Return the class of the message as the message name. You can override this
    # method to provide your own mapping from messages to names.
    #
    # @param [Object] message
    #
    # @return [Object] must be hashable and comparable by value; for example, a
    #         symbol, string, number or class makes a good message name
    #
    def message_name(message)
      message.class
    end

    #
    # Call +send_message+ method of the callback object, passing the message, and make the
    # transition.
    #
    # @param [Object] message to be sent
    #
    # @return [nil]
    #
    def send_message(message)
      raise 'not on the reactor thread' unless EM.reactor_thread?
      transition_on_send message_name(message), message do |msg|
        callback.send_message msg
      end
      nil
    end

    def receive_message(message)
      transition_on_recv message_name(message), message
    end

    #
    # Starts the state machine, setting it to the start state and executing the on_enter
    # handler on the start state. This method must be invoked inside the EM loop
    #
    # @return [nil]
    #
    def start
      @state = self.class.start_state
      @state_timer_sigs = []
      add_state_timer @state.timeout, &@state.on_timeout if @state.timeout
      @state.call_on_enter self, nil, nil
      nil
    end


    #
    # Stops the state machine, rarely needed. It must be invoked inside the EM loop
    #
    # @return [nil]
    #
    def stop
      cancel_state_timers
    end

  end


end