class Identity::NoticeResemblancesJob < ApplicationJob
  queue_as :default

  def perform(identity)
    ResemblanceNoticerEngine.run(identity)
  end
end
