module EventState
  #
  # Simulates a server that can do one job at a time. In this case, the job is
  # to sleep for a time determined by the client.
  #
  # It is intended mainly to test timeouts.
  #
  class JobServer < EventState::ObjectMachine
    SERVER_LISTEN_FOR_JOB_TIMEOUT = 1

    class ServerBusy; end
    class ServerFree; end

    protocol do
      state :start do
        on_enter do
          # note: this assumes that there's nothing else running in our reactor
          if EM.connection_count > 1
            send_message ServerBusy.new
          else
            send_message ServerFree.new
          end
        end

        on_send ServerBusy, :closed
        on_send ServerFree, :listening
      end

      state :listening do
        on_recv Float, :working

        timeout SERVER_LISTEN_FOR_JOB_TIMEOUT
      end

      state :working do
        on_enter do |delay|
          EM.defer proc {
            sleep delay
            "work: #{delay}"
          }, proc {|result|
            send_message result
          }
        end

        on_send String, :closed
      end

      state :closed do
        on_enter do
          close_connection_after_writing
        end
      end
    end
  end

  #
  # Client for JobServer.
  #
  class JobClient < EventState::ObjectMachine
    CLIENT_LISTEN_FOR_RESULT_TIMEOUT = 2
    ServerBusy = JobServer::ServerBusy
    ServerFree = JobServer::ServerFree

    def initialize send_delay, job_delay, log
      @send_delay = send_delay
      @job_delay = job_delay
      @log = log
    end

    protocol do
      state :start do
        on_enter do
          @log << "starting"
        end
        on_recv ServerBusy, :closed
        on_recv ServerFree, :sending
      end

      state :sending do
        on_send Float, :waiting

        on_enter do
          @log << "entering sending state"
          add_state_timer @send_delay do
            @log << "sending job"
            send_message @job_delay
          end
        end

        on_unbind do
          @log << "unbind in sending state"
        end
      end

      state :waiting do
        timeout CLIENT_LISTEN_FOR_RESULT_TIMEOUT do
          @log << "timed out in waiting state"
          close_connection
        end

        on_unbind do
          @log << "unbind in waiting state"
        end

        on_recv String, :closed
      end

      state :closed do
        on_enter ServerBusy do
          @log << "busy"
          close_connection
        end

        on_enter do |message|
          @log << "closed: #{message}"
          close_connection
        end
      end
    end
  end
end
