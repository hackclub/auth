module ResemblanceNoticerEngine
  class Base
    attr_reader :identity

    def initialize(identity)
      @identity = identity
    end

    def run
      raise NotImplementedError, "Subclasses must implement the run method"
    end
  end
end
