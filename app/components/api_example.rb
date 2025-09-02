class Components::APIExample < Components::Base
  extend Literal::Properties
  prop :method, _Nilable(String)
  prop :url, _Nilable(String)
  prop :path_only, _Boolean?

  def view_template
    div style: { margin: "10px 0" } do
      code style: { background: "black", padding: "0.2em", color: "white" } do
        span style: { color: "cyan" } do
          @method
        end
        plain " "
        copy_to_clipboard @url do
          if @path_only
            CGI.unescape(URI.parse(@url).tap { |u| u.host = u.scheme = u.port = nil }.to_s)
          else
            @url
          end
        end
      end
    end
  end
end
