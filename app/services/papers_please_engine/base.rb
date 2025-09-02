module PapersPleaseEngine
  class Base
    attr_reader :verification

    def initialize(verification)
      @verification = verification
    end

    def run
      raise NotImplementedError, "Subclasses must implement the run method"
    end
  end
end
