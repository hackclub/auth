class Components::Backend::ActionBar < Components::Base
  def initialize(controller_path: nil, action_name: nil, user: nil)
    @controller_path = controller_path
    @action_name = action_name
    @user = user
  end

  def view_template
    div id: "toolbar" do
      div class: "action_bar" do
        div class: "action_bar_left" do
          span(class: "usn", style: "margin-right: 3ch") { "Hack Club Auth" }
          yield if block_given?
        end
        div class: "action_bar_right" do
          render ActionButton.new(hotkey: "⌘-K", onclick: "window.openKbar()") { "GO" }
        end
        return unless current_shortcode.present?
        span(class: "current_shortcode") do
          "[#{current_shortcode.code}]"
        end
      end
    end
  end

  private

  def current_shortcode
    return nil unless @controller_path && @action_name

    @current_shortcode ||= Shortcodes.find_by_route(@controller_path, @action_name, @user)
  end
end