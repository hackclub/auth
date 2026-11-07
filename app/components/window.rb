# frozen_string_literal: true

class Components::Window < Components::Base
  extend Literal::Properties

  prop :window_title, String, :positional
  prop :close_url, _Nilable(String)
  prop :maximize_url, _Nilable(String)
  prop :max_width, Integer, default: 400.freeze

  def view_template
    div class: "window active", style: "max-width: #{@max_width}px" do
      div class: "title-bar" do
        div(class: "title-bar-text") { @window_title }
        if @close_url || @maximize_url
          div class: "title-bar-buttons" do
            button(data_maximize: "", data_navigate_url: @maximize_url) if @maximize_url
            button(data_close: "", data_navigate_url: @close_url) if @close_url
          end
        end
      end
      div class: "window-body" do
        yield
      end
    end
    script(nonce: helpers.content_security_policy_nonce) do
      raw safe <<~JS
        document.querySelectorAll('[data-navigate-url]').forEach(function(btn) {
          btn.addEventListener('click', function() {
            window.location.href = btn.dataset.navigateUrl;
          });
        });
      JS
    end
  end
end
