require "rails_helper"

RSpec.describe "Alpine event bindings in ERB templates" do
  {
    "app/views/developer_apps/edit.html.erb" => /x-on:click=|x-on:change=/,
    "app/views/developer_apps/new.html.erb" => /x-on:click=|x-on:change=/,
    "app/views/developer_apps/show.html.erb" => /x-on:click=/,
    "app/views/shared/verifications/_persona_name_check.html.erb" => /x-on:click\.prevent=/,
    "app/views/step_up/new.html.erb" => /x-on:click=/
  }.each do |path, pattern|
    it "#{path} keeps Alpine event attributes" do
      expect(File.read(Rails.root.join(path))).to match(pattern)
    end
  end
end
