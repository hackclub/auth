class DocsController < ApplicationController
  layout "docs"
  skip_before_action :authenticate_identity!, only: [ :index, :show ]

  before_action :set_doc_path, only: :show
  before_action :load_all_docs, only: [ :index, :show ]

  def index
    first_doc = @all_docs.first
    return render plain: "No documentation found" if first_doc.nil?
    
    redirect_to doc_path(slug: first_doc[:slug])
  end

  def show
    raise ActionController::RoutingError, "Documentation not found" unless File.exist?(@doc_file_path)

    @doc = parse_doc_file(@doc_file_path, params[:slug])
    render :show
  rescue StandardError => e
    raise if e.is_a?(ActionController::RoutingError)

    Rails.logger.error("Error parsing frontmatter for #{params[:slug]}: #{e.message}")
    @doc = {
      slug: params[:slug],
      title: "Error",
      content: "<p>Error parsing documentation.</p>"
    }
    render :show
  end

  private

  def set_doc_path
    slug = params[:slug] || "index"

    # Sanitize the slug to prevent directory traversal
    if slug.include?("..") || slug.include?("/")
      raise ActionController::RoutingError, "Invalid documentation path"
    end

    erb_path = Rails.root.join("app", "views", "docs", "#{slug}.md.erb")
    md_path = Rails.root.join("app", "views", "docs", "#{slug}.md")
    
    @doc_file_path = File.exist?(erb_path) ? erb_path : md_path
  end

  def load_all_docs
    @all_docs ||= begin
      docs_dir = Rails.root.join("app", "views", "docs")
      return [] unless Dir.exist?(docs_dir)

      Dir.glob(docs_dir.join("*.md{,.erb}")).map do |file_path|
        parsed = parse_frontmatter(file_path)
        next unless parsed

        slug = File.basename(file_path, ".*")
        slug = File.basename(slug, ".*") if file_path.end_with?(".md.erb")

        {
          slug: slug,
          title: parsed["title"] || slug.titleize,
          category: parsed["category"],
          order: parsed["order"] || 999,
          hidden: parsed["hidden"] || false
        }
      rescue => e
        Rails.logger.error("Error parsing doc #{file_path}: #{e.message}")
        nil
      end.compact.reject { |doc| doc[:hidden] }.sort_by { |doc| doc[:order] }
    end
  end

  def parse_frontmatter(file_path)
    cache_key = "doc_frontmatter:#{file_path}:#{File.mtime(file_path).to_i}"
    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      content = read_doc_content(file_path)
      FrontMatterParser::Parser.new(:md).call(content)
    end
  end

  def parse_doc_file(file_path, slug)
    cache_key = "doc_content:#{file_path}:#{File.mtime(file_path).to_i}"
    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      content = read_doc_content(file_path)
      parsed = FrontMatterParser::Parser.new(:md).call(content)

      {
        slug: slug,
        title: parsed["title"] || "Untitled",
        description: parsed["description"],
        category: parsed["category"],
        order: parsed["order"] || 999,
        content: render_markdown(parsed.content)
      }
    end
  end

  def read_doc_content(file_path)
    content = File.read(file_path)
    if file_path.to_s.end_with?(".erb")
      template = ERB.new(content)
      template.result(view_context.instance_eval { binding })
    else
      content
    end
  end

  def render_markdown(text)
    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener noreferrer" }
    )

    markdown = Redcarpet::Markdown.new(
      renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      superscript: true,
      highlight: true,
      footnotes: true
    )

    markdown.render(text).html_safe
  end
end
