module SlackService
  class << self
    def client = @client ||= Slack::Web::Client.new

    def find_by_email(email) = client.users_lookupByEmail(email:).dig("user", "id") rescue nil
  end
end
