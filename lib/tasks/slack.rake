# frozen_string_literal: true

namespace :slack do
  desc "Join all channels defined in config/slack_channels.yml"
  task join_channels: :environment do
    config = YAML.load_file(Rails.root.join("config/slack_channels.yml"))
    client = SlackService.client
    joined_ids = Set.new

    config.each do |env, channels|
      puts "\n=== #{env} ==="
      channels.each do |name, channel_id|
        next if joined_ids.include?(channel_id)

        joined_ids << channel_id
        print "Joining ##{name} (#{channel_id})... "
        client.conversations_join(channel: channel_id)
        puts "✓"
      rescue Slack::Web::Api::Errors::MethodNotSupportedForChannelType
        puts "skipped (DM or unsupported type)"
      rescue Slack::Web::Api::Errors::ChannelNotFound
        puts "not found"
      rescue Slack::Web::Api::Errors::SlackError => e
        puts "failed: #{e.message}"
      end
    end

    puts "\nDone!"
  end
end
