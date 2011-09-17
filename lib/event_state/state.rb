module EventState
  #
  # A state in a state machine. This class is for internal use; you will not
  # usually need to use it directly.
  #
  # Note that the <tt>Proc</tt>s stored here are executed in the context of an
  # instance of a subclass of {Machine}, rather than in the context in which
  # they were defined.
  #
  # @attr [Symbol] name state name
  #
  # @attr [Hash<Symbol, Proc>] on_enters map from message names to handlers
  #
  # @attr [Proc, nil] default_on_enter called when the state is entered via a
  #       message that does not have an associated handler in +on_enters+
  #
  # @attr [Hash<Symbol, Proc>] on_exits map from message names to handlers
  #
  # @attr [Proc, nil] default_on_exit called when the state is exited via a
  #       message that does not have an associated handler in +on_exits+
  #
  # @attr [Hash<Symbol, Symbol>] on_sends map from message names to successor
  #       state names
  #
  # @attr [Hash<Symbol, Symbol>] on_recvs map from message names to successor
  #       state names
  #
  State = Struct.new(:name,
    :on_enters, :default_on_enter,
    :on_exits,  :default_on_exit,
    :on_sends,  :on_recvs) do
    def initialize(*)
      super
      self.on_enters ||= {}
      self.on_exits  ||= {}
      self.on_sends  ||= {}
      self.on_recvs  ||= {}
    end

    #
    # @private
    #
    def call_on_enter context, message_name, message
      call_state_handler context, on_enters, default_on_enter,
        message_name, message
    end

    #
    # @private
    #
    def call_on_exit context, message_name, message
      call_state_handler context, on_exits, default_on_exit,
        message_name, message
    end

    private

    def call_state_handler context, handlers, default_handler,
      message_name, message

      # use message-specific handler if it exists; otherwise use the default
      handler = handlers[message_name] || default_handler

      # evaluate the block in the right context, namely the machine instance
      context.instance_exec(message, &handler) if handler 
    end
  end
end
