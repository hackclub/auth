module DocsHelper
  def docs_by_category
    @all_docs.group_by { |doc| doc[:category] || "General" }
  end

  def active_doc?(doc_slug)
    params[:slug] == doc_slug || (params[:slug].nil? && doc_slug == @all_docs.first&.dig(:slug))
  end

  def doc_nav_link(doc)
    classes = [ "doc-nav-link" ]
    classes << "active" if active_doc?(doc[:slug])

    link_to doc[:title], doc_path(slug: doc[:slug]), class: classes.join(" ")
  end
end
