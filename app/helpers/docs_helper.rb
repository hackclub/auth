module DocsHelper
  def docs_by_category
    @all_docs.group_by { |doc| doc[:category] || "General" }
  end

  def doc_nav_link(doc)
    link_to doc[:title], doc_path(slug: doc[:slug]), 
            class: "docs-nav-link #{'active' if @doc && @doc[:slug] == doc[:slug]}"
  end

  def stub_identity_with_address(identity)
    address = FactoryBot.build_stubbed(:address, identity: identity)
    identity.define_singleton_method(:addresses) { [address] }
    identity.define_singleton_method(:primary_address) { address }
    identity
  end

  def render_api_example(template:, identity: nil, identities: nil, scopes: ["name"])
    require "factory_bot_rails"
    
    controller = API::V1::IdentitiesController.new
    
    if identity
      controller.instance_variable_set(:@identity, identity)
    end
    
    if identities
      controller.instance_variable_set(:@identities, identities)
    end
    
    controller.define_singleton_method(:current_scopes) { scopes }
    
    json_result = controller.render_to_string(
      template: template,
      formats: [:json]
    )
    
    JSON.pretty_generate(JSON.parse(json_result))
  end
end
