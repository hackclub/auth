class Components::Backend::ActionButton < Components::Base
  extend Literal::Properties

  prop :hotkey, _String?
  prop :onclick, _String?
  prop :selected, _Boolean?

  def view_template
    div class: "action_button#{" selected" if @selected}", onclick: (safe(@onclick) if @onclick) do
      span(class: "hotkey") { @hotkey } if @hotkey.present?
      span class: "content" do
        yield
      end
    end
  end
end
