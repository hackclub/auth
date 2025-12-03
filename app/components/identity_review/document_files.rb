# frozen_string_literal: true

class Components::IdentityReview::DocumentFiles < Components::Base
  def initialize(document)
    @document = document
  end

  def view_template
    if @document.files.attached?
      div class: "document-files" do
        @document.files.each_with_index do |file, index|
          render_file(file, index)
        end
      end

      script do
        raw safe <<~JAVASCRIPT
          function rotateImage(index) {
            const img = document.getElementById('image-' + index);
            let currentRotation = parseInt(img.dataset.rotation || 0);
            currentRotation = (currentRotation + 90);
            img.dataset.rotation = currentRotation;
            img.style.transform = 'rotate(' + currentRotation + 'deg)';
          }
        JAVASCRIPT
      end
    else
      div(class: "empty-state") { "no files attached" }
    end
  end

  private

  def render_file(file, index)
    div class: "document-file" do
      div class: "file-header" do
        span(class: "file-name") { "#{index + 1}. #{file.filename}" }
        a(href: url_for(file), target: "_blank", class: "file-action") { "open ↗" }
      end

      if file.content_type.start_with?("image/")
        render_image(file, index)
      elsif file.content_type == "application/pdf"
        render_pdf(file)
      else
        render_other(file)
      end
    end
  end

  def render_image(file, index)
    image_src = if file.content_type.in?(%w[image/heic image/heif])
      url_for(file.variant(format: :png))
    else
      url_for(file)
    end

    div class: "file-preview" do
      div id: "loader-#{index}", class: "file-loader" do
        plain file.content_type.in?(%w[image/heic image/heif]) ? "converting heic..." : "loading..."
        br
        vite_image_tag "images/loader.gif", class: "loader-gif"
      end

      div id: "image-container-#{index}", class: "image-container hidden" do
        img(
          src: image_src,
          alt: "document file #{index + 1}",
          class: "preview-image",
          id: "image-#{index}",
          data: { rotation: 0 },
          onload: safe("document.getElementById('loader-#{index}').style.display='none'; document.getElementById('image-container-#{index}').classList.remove('hidden');"),
          onerror: safe("document.getElementById('loader-#{index}').innerHTML='error loading image';"),
        )
        button(
          type: "button",
          class: "action_button rotate-button",
          onclick: safe("rotateImage(#{index})"),
        ) { "↻ rotate" }
      end
    end
  end

  def render_pdf(file)
    div class: "file-preview pdf-preview" do
      iframe(
        src: url_for(file),
        class: "pdf-frame",
        type: "application/pdf",
      ) do
        p(class: "pdf-fallback") do
          plain "browser doesn't support pdf embedding. "
          a(href: url_for(file), target: "_blank") { "open pdf" }
        end
      end
    end
  end

  def render_other(file)
    div class: "file-preview lowered" do
      detail_row("type", file.content_type)
      detail_row("download") do
        a(href: url_for(file), target: "_blank") { "download file" }
      end
    end
  end

  def detail_row(label, value = nil, &block)
    div class: "detail-row" do
      span(class: "detail-label") { label }
      span class: "detail-value" do
        if block_given?
          yield
        else
          plain value.to_s
        end
      end
    end
  end
end
