module EventState

  #
  # Receives a message and sends it back.
  #
  class HookableEchoMachine < HookableMachine
    protocol do
      state :listening do
        on_recv String, :speaking
      end

      state :speaking do
        on_enter do |message|
          send_message message
        end

        on_send String, :listening
      end
    end
  end



end