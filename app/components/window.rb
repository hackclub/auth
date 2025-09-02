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
            button(data_maximize: "", onclick: safe("window.location.href='#{@maximize_url}'")) if @maximize_url
            button(data_close: "", onclick: safe("window.location.href='#{@close_url}'")) if @close_url
          end
        end
      end
      div class: "window-body" do
        yield
      end
    end
  end
end
