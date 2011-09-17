module EventState
  #
  # Base class for state machines driven by +EventMachine+.
  #
  # This class provides a domain-specific language (DSL) for declaring the
  # structure of the machine. See the {file:README} for examples and the general
  # idea of how this works.
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
  class Machine < EventMachine::Connection

    class << self
      #
      # Declare a state; pass a block to configure the state using {on_enter},
      # {on_send} and so on.
      #
      # By default, the machine's start state is the first state declared using
      # this method.
      #
      # @yield [] configure the state
      #
      # @return [nil]
      #
      def state state_name
        # initialize instance variables on first call (avoid warnings)
        unless defined?(@state)
          @state = nil
          @start_state = nil
          @states = {}
        end

        # can't nest these calls
        raise "cannot nest calls to state" if @state

        # create new state or edit exiting state
        @state = @states[state_name] || State.new(state_name)

        # configure this state 
        yield

        # need to know the start state
        @start_state = @state if @states.empty?

        # index by name for easy lookup
        @states[@state.name] = @state

        # ensure that on_enter etc. aren't callable outside of a state block
        @state = nil
      end

      #
      # Register a block to be called after the machine enters the current
      # {state}.
      #
      # The machine changes state in response to a message being sent or
      # received, and you can register an {on_enter} handler that is specific
      # to the message that caused the change. Or you can render a catch-all
      # block that will be called if no more specific handler was found (see
      # example below).
      #
      # If a catch-all +on_enter+ block is given for the {start_state}, it is
      # called from EventMachine's +post_init+ method. In this case (and only
      # this case), the message passed to the block is +nil+.
      #
      # @example
      #   state :foo do
      #     on_enter :my_message do |message|
      #       # got here due to a :my_message message
      #     end
      #
      #     on_enter do
      #       # got here some other way
      #     end
      #   end
      #
      # @param [Array<Symbol>] message_names zero or more
      #
      # @yield [message]
      #
      # @yieldparam [Message, nil] message nil iff this is the start state and
      #             the machine has just started up (called from +post_init+)
      #
      # @return [nil]
      #
      def on_enter *message_names, &block
        raise "on_enter must be called from a state block" unless @state
        if message_names == []
          raise "on_enter block already given" if @state.default_on_enter
          @state.default_on_enter = block
        else
          save_state_handlers('on_enter', @state.on_enters, message_names,block)
        end
        nil
      end

      #
      # Register a block to be called after the machine exits the current
      # {state}. See {on_enter} for more information.
      #
      # TODO maybe this should be called from +unbind+ if the machine stops in
      # the current state
      #
      # @param [Array<Symbol>] message_names zero or more
      #
      # @yield [message]
      #
      # @yieldparam [Message] message
      #
      # @return [nil]
      #
      def on_exit *message_names, &block
        raise "on_exit must be called from a state block" unless @state
        if message_names == []
          raise "on_exit block already given" if @state.default_on_exit
          @state.default_on_exit = block
        else
          save_state_handlers('on_exit', @state.on_exits, message_names, block)
        end
        nil
      end

      #
      # Declare which state the machine transitions to when one of the given
      # messages is sent in this {state}.
      #
      # @example
      #   state :foo do
      #     on_enter do
      #       EM.defer do
      #         sleep 3
      #         send_message :done
      #       end
      #     end
      #     on_send :done, :bar
      #   end
      #
      # @param [Array<Symbol>] message_names one or more
      #
      # @param [Symbol] next_state_name
      #
      # @return [nil]
      #
      def on_send *message_names, next_state_name
        raise "on_send must be called from a state block" unless @state
        message_names.flatten.each do |name|
          @state.on_sends[name] = next_state_name
        end
      end

      #
      # Declare which state the machine transitions to when one of the given
      # messages is received in this {state}. See {on_send} for more
      # information.
      #
      # @param [Array<Symbol>] message_names one or more
      #
      # @param [Symbol] next_state_name
      #
      # @return [nil]
      #
      def on_recv *message_names, next_state_name
        raise "on_recv must be called from a state block" unless @state
        message_names.flatten.each do |name|
          @state.on_recvs[name] = next_state_name
        end
      end

      def on_protocol_error &block
        if block_given?
          @on_protocol_error = block
          nil
        else
          # set default
          @on_protocol_error ||= proc {|message|
            raise "bad message: #{$!.inspect}"
          }

          @on_protocol_error
        end
      end

      #
      # @return [Hash<Symbol, State>] map from state names (ruby symbols) to
      #         {State}s
      #
      attr_reader :states

      #
      # @return [State] the machine enters this state when a new connection is
      #         established
      #
      attr_reader :start_state

      #
      # @private
      #
      def transitions
        states.values.map{|state|
          [[state.on_sends, :send], [state.on_recvs, :recv]].map {|pairs, kind|
            pairs.map{|message, next_state_name|
              [state.name, kind, message, next_state_name]}}}.flatten(2)
      end

      #
      # Print the state machine in dot (graphviz) format.
      #
      # The 'send' edges are red and 'receive' edges are blue, and the start
      # state is indicated by a double border.
      #
      # @param [IO, nil] io if +nil+, the dot file is returned as a string; if
      #        not nil, the dot file is written to +io+ 
      # 
      # @param [String] graph_options specify dot graph options
      #
      # @return [String, nil] if +io+ is +nil+, returns the dot source as a
      #         string; if +io+ is not +nil+, this method returns +nil+
      #
      def print_state_machine_dot io=nil, graph_options=''
        out = io || StringIO.new

        out.puts "digraph #{self.name.inspect} {\n  #{graph_options}"

        out.puts "  #{start_state.name} [peripheries=2];" # double border
        
        transitions.each do |state_name, kind, message_name, next_state_name|
          style = case kind
                  when :recv then
                    "color=blue,label=\"#{message_name}\""
                  when :send then
                    "color=red,label=\"#{message_name}\""
                  else 
                    raise "unknown kind #{kind}"
                  end
          out.puts "  #{state_name} -> #{next_state_name} [#{style}];"
        end
        out.puts "}"

        out.string unless io
      end

      private

      def save_state_handlers handler_type, handlers, message_names, block
        message_names.flatten.each do |name|
          raise "#{handler_type} already defined for #{name}" if handlers[name]
          handlers[name] = block
        end
      end 
    end

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
    # Move the state machine from its current state to the successor state that
    # it should be in after receiving the given +message+, according to the
    # protocol defined using the DSL.
    #
    # If the received message is not valid according to the protocol, then the
    # protocol error handler is called (see {on_protocol_error}). 
    #
    # The precise order of events is:
    # 1. the +on_exit+ handler of the current state is called with +message+ 
    # 2. the current state is set to the successor state
    # 3. the +on_enter+ handler of the new current state is called with
    #    +message+
    #
    # @param [Object] message_name the name for +message+; this is what relates
    #        the message data to the transitions defined with {on_send}; must be
    #        hashable and comparable by value; for example, a symbol, string,
    #        number or class makes a good message name
    #
    # @param [Object] message received
    #
    # @return [nil]
    #
    def transition_on_recv message_name, message
      puts "#{self.class}: RECV #{message_name} #{message.inspect}"
      # look up successor state
      next_state_name = @state.on_recvs[message_name]

      # if there is no registered successor state, it's a protocol error
      if next_state_name.nil?
        self.class.on_protocol_error.call(message)
      else
        transition message_name, message, next_state_name
      end

      nil
    end

    #
    # Move the state machine from its current state to the successor state that
    # it should be in after sending the given +message+, according to the
    # protocol defined using the DSL.
    #
    # If the message to be sent is not valid according to the protocol, then the
    # protocol error handler is called (see {on_protocol_error}). If
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
    # @param [Object] message_name the name for +message+; this is what relates
    #        the message data to the transitions defined with {on_send}; must be
    #        hashable and comparable by value; for example, a symbol, string,
    #        number or class makes a good message name
    #
    # @yield [message] should actually send the message, typically using
    #        EventMachine's +send_data+ method
    #
    # @yieldparam [Object] message the same message passed to this method
    #
    # @return [nil]
    #
    def transition_on_send message_name, message
      puts "#{self.class}: SEND #{message_name} #{message.inspect}"
      # look up successor state
      next_state_name = @state.on_sends[message_name]

      # if there is no registered successor state, it's a protocol error
      if next_state_name.nil?
        self.class.on_protocol_error.call(message)
      else
        # let the caller send the message before we transition
        yield message if block_given?
        
        transition message_name, message, next_state_name
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

