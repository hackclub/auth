# frozen_string_literal: true

namespace :analytics do
  desc "Create analytics database"
  task create: :environment do
    config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "analytics")
    ActiveRecord::Tasks::DatabaseTasks.create(config)
    puts "Created analytics database: #{config.database}"
  end

  desc "Drop analytics database"
  task drop: :environment do
    config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "analytics")
    ActiveRecord::Tasks::DatabaseTasks.drop(config)
    puts "Dropped analytics database: #{config.database}"
  end

  desc "Migrate analytics database"
  task migrate: :environment do
    ActiveRecord::Base.establish_connection(:analytics)
    ActiveRecord::MigrationContext.new("db/analytics_migrate").migrate
    puts "Migrated analytics database"
  end

  desc "Rollback analytics database"
  task rollback: :environment do
    ActiveRecord::Base.establish_connection(:analytics)
    ActiveRecord::MigrationContext.new("db/analytics_migrate").rollback
    puts "Rolled back analytics database"
  end

  desc "Reset analytics database (drop, create, migrate)"
  task reset: [ :drop, :create, :migrate ]

  desc "Purge old analytics data (default: keep 90 days)"
  task :purge, [ :days ] => :environment do |_, args|
    days = (args[:days] || 90).to_i
    cutoff = days.days.ago

    puts "Purging analytics data older than #{cutoff}"

    events_deleted = Ahoy::Event.where("time < ?", cutoff).delete_all
    puts "Deleted #{events_deleted} events"

    # Delete visits that have no remaining events
    visits_deleted = Ahoy::Visit
      .where("started_at < ?", cutoff)
      .where.not(id: Ahoy::Event.select(:visit_id).where.not(visit_id: nil))
      .delete_all
    puts "Deleted #{visits_deleted} orphaned visits"

    puts "Done"
  end

  desc "Show analytics database stats"
  task stats: :environment do
    puts "Analytics Database Stats"
    puts "=" * 40
    puts "Total visits: #{Ahoy::Visit.count}"
    puts "Total events: #{Ahoy::Event.count}"
    puts ""
    puts "Events by name:"
    Ahoy::Event.group(:name).count.sort_by { |_, v| -v }.each do |name, count|
      puts "  #{name}: #{count}"
    end
    puts ""
    puts "Last 7 days:"
    puts "  Visits: #{Ahoy::Visit.where("started_at > ?", 7.days.ago).count}"
    puts "  Events: #{Ahoy::Event.where("time > ?", 7.days.ago).count}"
  end
end
