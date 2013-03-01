require 'eventmachine'

require 'event_state/version'
require 'event_state/state'
require 'event_state/simple_machine'
require 'event_state/machine'
require 'event_state/object_machine'
require 'event_state/hookable_machine'

#
# See the {file:README} for details.
#
module EventState

  #
  # Base class for {SendProtocolError} and {RecvProtocolError}.
  #
  # You can catch these errors by registering a block with
  # <tt>EventMachine.error_handler</tt>.
  #
  class ProtocolError < RuntimeError
    def initialize machine, state_name, action, message_name, data
      @machine, @state_name, @action, @message_name, @data =
        machine, state_name, action, message_name, data
    end

    #
    # @return [Machine] the machine that raised the error
    #
    attr_reader :machine

    #
    # @return [Symbol] the name of the state in which the error occurred
    #
    attr_reader :state_name

    #
    # @return [:recv, :send] whether the error occurred on a send or a receive
    #
    attr_reader :action

    #
    # @return [Object] the name of the message sent or received
    #
    attr_reader :message_name

    #
    # @return [Object] the message / data sent or received
    #
    attr_reader :data

    #
    # @return [String]
    #
    def inspect
      "#<#{self.class}: for #{machine.class} in"\
        " #{state_name.inspect} state: #{action} #{message_name}>"
    end
  end

  #
  # Error raised by {Machine} when a message that is invalid according to the
  # machine's protocol is sent.
  #
  class SendProtocolError < ProtocolError
    def initialize machine, state_name, message_name, data
      super machine, state_name, :send, message_name, data
    end
  end

  #
  # Error raised by {Machine} when a message that is invalid according to the
  # machine's protocol is received.
  #
  class RecvProtocolError < ProtocolError
    def initialize machine, state_name, message_name, data
      super machine, state_name, :recv, message_name, data
    end
  end
end
