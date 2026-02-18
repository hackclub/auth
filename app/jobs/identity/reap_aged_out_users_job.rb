class Identity::ReapAgedOutUsersJob < ApplicationJob
  queue_as :default

  def perform
    aged_out = Identity.where(ysws_eligible: true, hq_override: [false, nil])
                       .where("birthday <= ?", 19.years.ago.to_date)

    reaped_count = 0

    aged_out.find_each do |identity|
      identity.update!(ysws_eligible: false, is_alum: true)
      identity.create_activity :aged_out, recipient: identity
      reaped_count += 1
    end

    Rails.logger.info "ReapAgedOutUsersJob: marked #{reaped_count} #{"user".pluralize reaped_count} as alumni and ineligible"
  end
end