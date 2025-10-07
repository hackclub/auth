class Components::EnvironmentBanner < Components::Base
  def view_template
    case Rails.env.to_s
    when "staging"
      div(class: "banner purple") do
        safe "this is a staging environment. <b>do not upload any actual personal information here.</b>"
      end
    when "development"
      div(class: "banner success") do
        plain "you're in dev! go nuts :3"
      end
    end
  end
end
