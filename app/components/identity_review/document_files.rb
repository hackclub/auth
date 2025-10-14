class Components::IdentityReview::DocumentFiles < Components::Base
  def initialize(document)
    @document = document
  end

  def view_template
    h2(style: "margin-top: 0;") { "Document Files" }

    if @document.files.attached?
      @document.files.each_with_index do |file, index|
        div(style: "margin-bottom: 2rem;") do
          h3 { "File #{index + 1}: #{file.filename}" }

          if file.content_type.start_with?("image/")
            # Display image files (use variants for format conversion)
            image_src = if file.content_type.in?(%w[image/heic image/heif])
                helpers.url_for(file.variant(format: :png))
            else
                helpers.url_for(file)
            end

            div(style: "position: relative; display: inline-block;") do
              # Loader
              div(
                id: "loader-#{index}",
                style: "display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 200px; border: 1px solid #ddd; border-radius: 4px; background: #f9f9f9;",
              ) do
                div(style: "text-align: center;") do
                  plain file.content_type.in?(%w[image/heic image/heif]) ? "Converting HEIC image..." : "Loading image..."
                  br
                  vite_image_tag "images/loader.gif", style: "image-rendering: pixelated; width: 32px; height: 32px;"
                end
              end

              # Image container (hidden until loaded)
              div(id: "image-container-#{index}", style: "display: none;") do
                img(
                  src: image_src,
                  alt: "Document file #{index + 1}",
                  style: "max-width: 100%; max-height: 600px; height: auto; border: 1px solid #ddd; border-radius: 4px; transition: transform 0.3s ease;",
                  id: "image-#{index}",
                  data: { rotation: 0 },
                  onload: safe("document.getElementById('loader-#{index}').style.display='none'; document.getElementById('image-container-#{index}').style.display='block';"),
                  onerror: safe("document.getElementById('loader-#{index}').innerHTML='<p>Error loading image</p>';"),
                )
                button(
                  type: "button",
                  class: "button",
                  style: "position: absolute; top: 10px; right: 10px;",
                  onclick: safe("rotateImage(#{index})"),
                  title: "Rotate image",
                ) { "↻ Rotate" }
              end
            end
          elsif file.content_type == "application/pdf"
            # Display PDF files inline
            div(style: "border: 1px solid #ddd; border-radius: 4px; background: #f9f9f9;") do
              div(style: "padding: 1rem; border-bottom: 1px solid #ddd; background: #f5f5f5;") do
                span(style: "font-weight: bold;") { "#{helpers.inline_icon("docs", size: 16)} #{file.filename}" }
                a(
                  href: helpers.url_for(file),
                  target: "_blank",
                  style: "color: #0066cc; text-decoration: underline; margin-left: 1rem;",
                ) { "Open in new tab" }
              end
              # Embed PDF using iframe
              iframe(
                src: helpers.url_for(file),
                width: "100%",
                height: "600",
                style: "border: none; display: block;",
                type: "application/pdf",
              ) do
                # Fallback for browsers that don't support PDF embedding
                p(style: "padding: 2rem; text-align: center;") do
                  plain "Your browser doesn't support PDF embedding. "
                  a(
                    href: helpers.url_for(file),
                    target: "_blank",
                    style: "color: #0066cc; text-decoration: underline;",
                  ) { "Click here to view the PDF" }
                end
              end
            end
          else
            # Display other file types
            div(style: "border: 1px solid #ddd; border-radius: 4px; padding: 1rem; background: #f9f9f9;") do
              p { "#{helpers.inline_icon("attachment", size: 16)} File: #{file.filename}" }
              p { "Type: #{file.content_type}" }
              p do
                a(
                  href: helpers.url_for(file),
                  target: "_blank",
                  style: "color: #0066cc; text-decoration: underline;",
                ) { "Download File" }
              end
            end
          end
        end
      end
    else
      p(style: "color: #666; font-style: italic;") { "No files attached to this document." }
    end

    # Add JavaScript for image rotation
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
  end
end
