module EventState
  module Message
    def to_sym
      base_name = self.class.name.split('::').last
      base_name.gsub(/([A-Z])/) { "_#{$1.downcase}" }[1..-1].to_sym
    end
  end

  class MessageStruct < Struct
    include EventState::Message
  end
end
