class InstallRailsPulseTables < ActiveRecord::Migration[8.0]
  def change
    schema_file = Rails.root.join("db", "rails_pulse_schema.rb")

    unless File.exist?(schema_file)
      raise "Rails Pulse schema file not found at #{schema_file}"
    end

    say_with_time "Loading Rails Pulse schema from #{schema_file}" do
      load schema_file
      say "Rails Pulse tables created successfully"
      say "The schema file #{schema_file} remains as your single source of truth"
    end
  end
end
