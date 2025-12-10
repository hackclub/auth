class Slack::BackyardgardenJoinFlow < ApplicationJob
    queue_as :default

    def first_email_send(identity)
        BackyardGarden_Mailer.first_email(identity).deliver_now
    end
end