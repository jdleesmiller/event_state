module EventState
  #
  # Interface for a message that can be sent or received by a {Machine}.
  #
  # Messages do not have to implement this interface; it is required only that
  # the message responds to +to_sym+, and that +to_sym+ returns a message name
  # that is valid for the machine. Note that a ruby symbol is a valid message.
  #
  # This module provides a default implementation of {#to_sym} that returns a
  # message name based on the name of the implementing class.
  #
  module Message
    #
    # Default message name based on the class that includes this module; for
    # example, +MyMessage+ becomes <tt>:my_message</tt>.
    #
    # @return [Symbol]
    #
    def to_sym
      Message.class_name_to_message_name(self.class.name)
    end

    #
    # Convert class name to message name; for example, +MyMessage+ becomes
    # <tt>:my_message</tt>. This is what the default {#to_sym} uses internally.
    #
    # @param [String] class_name
    #
    # @return [Symbol]
    #
    def self.class_name_to_message_name class_name
      base_name = class_name.split('::').last
      base_name.gsub(/([A-Z])/) { "_#{$1.downcase}" }[1..-1].to_sym
    end
  end

  #
  # Shorthand for creating a ruby +Struct+ that includes the {Message} module.
  # This
  #
  #  MyMessage = EventState::MessageStruct.new(:foo)
  #
  # is equivalent to this
  #
  #  MyMessage = Struct.new(:foo) do
  #    include EventState::Message
  #  end
  #
  class MessageStruct < Struct
    include EventState::Message
  end
end
