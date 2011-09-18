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
    class << self
      #
      # Declare the protocol; pass a block to declare the {state}s.
      #
      # When the block terminates, this method declares any 'implicit' states
      # that have been referenced by {on_send} or {on_recv} but that have not
      # been declared with {state}. It also does some basic sanity checking.
      #
      # There can be multiple protocol blocks declared for one class; it is
      # equivalent to moving all of the definitions to the same block.
      #
      # @yield [] declare the {state}s in the protocol
      #
      # @return [nil]
      #
      def protocol
        raise "cannot nest protocol blocks" if defined?(@protocol) && @protocol

        @start_state = nil unless defined?(@start_state)
        @states = {}       unless defined?(@states)

        @protocol = true
        @state = nil
        yield
        @protocol = false

        # add implicitly defined states to @states to avoid having to check for
        # nil states while the machine is running
        explicit_states = Set[*@states.keys]
        all_states = Set[*@states.values.map {|state|
          state.on_sends.values + state.on_recvs.values}.flatten]
        implicit_states = all_states - explicit_states
        implicit_states.each do |state_name|
          @states[state_name] = State.new(state_name)
        end
      end

      # 
      # Exchange sends for receives and receives for sends in the +base+
      # protocol, and clear all of the {on_enter} and {on_exit} handlers. It
      # often happens that a server and a client follow protocols with the same
      # states, but with sends and receives interchanged. This method is
      # intended to help with this case. You can, for example, reverse a server
      # and use the passed block to define new {on_enter} and {on_exit} handlers
      # appropriate for the client.
      #
      # The start state is determined by the first state declared in the given
      # block (not by the protocol being reversed).
      #
      # @param [Class] base
      #
      # @yield [] define {state}s new {on_enter} and {on_exit} handlers
      #
      # @return [nil]
      #
      def reverse_protocol base, &block
        raise "cannot mirror if already have a protocol" if defined?(@protocol)

        @states = Hash[base.states.map {|state_name, state|
          new_state = EventState::State.new(state_name)
          new_state.on_recvs = state.on_sends.dup
          new_state.on_sends = state.on_recvs.dup
          [state_name, new_state]
        }]

        protocol(&block)
      end

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
        raise "must be called from within a protocol block" unless @protocol
        raise "cannot nest calls to state" if @state

        # create new state or edit exiting state
        @state = @states[state_name] || State.new(state_name)

        # configure this state 
        yield

        # need to know the start state
        @start_state = @state unless @start_state

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
      #       EM.defer proc { sleep 3 },
      #                proc { send_message DoneMessage.new(42) }
      #     end
      #     on_send DoneMessage, :bar
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
      # Called when EventMachine calls +unbind+ on the connection while it is in
      # the current state. This may indicate that the connection has been closed
      # or timed out. The default is to take no action.
      #
      # @yield [] called upon +unbind+
      #
      # @return [nil]
      #
      def on_unbind &block
        raise "on_unbind must be called from a state block" unless @state
        @state.on_unbind = block
        nil
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
      # The complete list of transitions declared in the state machine (an edge
      # list).
      #
      # @return [Array] each entry is of the form <tt>[state_name, [:send |
      #         :recv, message_name], next_state_name]</tt>
      #
      def transitions
        states.values.map{|state|
          [[state.on_sends, :send], [state.on_recvs, :recv]].map {|pairs, kind|
            pairs.map{|message, next_state_name|
              [state.name, [kind, message], next_state_name]}}}.flatten(2)
      end

      #
      # Print the state machine in dot (graphviz) format.
      #
      # By default, the 'send' edges are red and 'receive' edges are blue, and
      # the start state is indicated by a double border.
      #
      # @param [Hash] opts extra options
      #
      # @option opts [IO] :io (StringIO.new) to print to
      #
      # @option opts [String] :graph_options ('') dot graph options
      #
      # @option opts [Proc] :message_name_transform transform message names
      #
      # @option opts [Proc] :state_name_form transform state names
      #
      # @option opts [String] :recv_edge_style ('color=blue')
      #
      # @option opts [String] :send_edge_style ('color=red')
      #
      # @return [IO] the +:io+ option
      #
      def print_state_machine_dot opts={}
        io                     = opts[:io] || StringIO.new
        graph_options          = opts[:graph_options] || ''
        message_name_transform = opts[:message_name_transform] || proc {|x| x}
        state_name_transform   = opts[:state_name_transform] || proc {|x| x}
        recv_edge_style        = opts[:recv_edge_style] || 'color=blue'
        send_edge_style        = opts[:send_edge_style] || 'color=red'

        io.puts "digraph #{self.name.inspect} {\n  #{graph_options}"

        io.puts "  #{start_state.name} [peripheries=2];" # double border
        
        transitions.each do |state_name, (kind, message_name), next_state_name|
          s0 = state_name_transform.call(state_name)
          s1 = state_name_transform.call(next_state_name)
          label = message_name_transform.call(message_name)

          style = case kind
                  when :recv then
                    "#{recv_edge_style},label=\"#{label}\""
                  when :send then
                    "#{send_edge_style},label=\"#{label}\""
                  else 
                    raise "unknown kind #{kind}"
                  end
          io.puts "  #{s0} -> #{s1} [#{style}];"
        end
        io.puts "}"

        io
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
    # Called by +EventMachine+ when a connection is closed. This calls the
    # {on_unbind} handler for the current state. 
    #
    # @return [nil]
    #
    def unbind
      puts "#{self.class} UNBIND"
      handler = @state.on_unbind
      self.instance_exec(&handler) if handler 
      nil
    end

    #
    # Move the state machine from its current state to the successor state that
    # it should be in after receiving the given +message+, according to the
    # protocol defined using the DSL.
    #
    # If the received message is not valid according to the protocol, then the
    # protocol error handler is called (see {ProtocolError}). 
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
        raise RecvProtocolError.new(self, @state.name, message_name, message)
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
    # protocol error handler is called (see {ProtocolError}). If
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
        raise SendProtocolError.new(self, @state.name, message_name, message)
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

