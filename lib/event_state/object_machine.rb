module EventState
  #
  # Base class for a machine in which the messages are ruby objects. See the
  # {file:README} for examples.
  #
  class ObjectMachine < Machine
    include EventMachine::P::ObjectProtocol

    #
    # Return the class of the message as the message name. You can override this
    # method to provide your own mapping from messages to names.
    #
    # @param [Object] message
    #
    # @return [Object] must be hashable and comparable by value; for example, a
    #         symbol, string, number or class makes a good message name
    #
    def message_name message
      message.class
    end

    #
    # Called by +EventMachine+ (actually, the +ObjectProtocol+) when a message
    # is received; makes the appropriate transition.
    #
    # Note: if you want to receive non-messages as well, you should override
    # this method in your subclass, and call +super+ only when a message is
    # received.
    #
    # @param [Object] message received
    #
    # @return [nil]
    #
    def receive_object message
      transition_on_recv message_name(message), message
    end

    #
    # Call <tt>ObjectProtocol</tt>'s +send_object+ on the message and make the
    # transition.
    #
    # @param [Object] message to be sent
    #
    # @return [nil]
    #
    def send_message message
      raise "not on the reactor thread" unless EM.reactor_thread?
      transition_on_send message_name(message), message do |msg|
        send_object msg
      end
    end
  end
end

