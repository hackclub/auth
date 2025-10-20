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
    unless File.exist?(@doc_file_path)
      raise ActionController::RoutingError, "Documentation not found"
    end

    content = File.read(@doc_file_path)
    parsed = FrontMatterParser::Parser.new(:md).call(content)

    @doc = {
      slug: params[:slug],
      title: parsed["title"] || "Untitled",
      description: parsed["description"],
      category: parsed["category"],
      order: parsed["order"] || 999,
      content: render_markdown(parsed.content)
    }
    render :show
  rescue FrontMatterParser::SyntaxError => e
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

    @doc_file_path = Rails.root.join("app", "views", "docs", "#{slug}.md")
  end

  def load_all_docs
    docs_dir = Rails.root.join("app", "views", "docs")
    return @all_docs = [] unless Dir.exist?(docs_dir)

    @all_docs = Dir.glob(docs_dir.join("*.md")).map do |file_path|
      content = File.read(file_path)
      parsed = FrontMatterParser::Parser.new(:md).call(content)

      {
        slug: File.basename(file_path, ".md"),
        title: parsed["title"] || File.basename(file_path, ".md").titleize,
        category: parsed["category"],
        order: parsed["order"] || 999,
        hidden: parsed["hidden"] || false
      }
    rescue => e
      Rails.logger.error("Error parsing doc #{file_path}: #{e.message}")
      nil
    end.compact.reject { |doc| doc[:hidden] }.sort_by { |doc| doc[:order] }
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
