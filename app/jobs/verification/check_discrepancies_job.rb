class Verification::CheckDiscrepanciesJob < ApplicationJob
  queue_as :default

  def perform(verification)
    PapersPleaseEngine.run(verification)
  end
end
