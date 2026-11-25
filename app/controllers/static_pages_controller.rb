class StaticPagesController < ApplicationController
  skip_before_action :authenticate_identity!, only: [ :external_api_docs, :welcome, :oauth_welcome ]

  def home
    @sso_apps = SAMLService::Entities.service_providers.values.select do |sp|
      sp[:allow_idp_initiated] && SAMLService::Access.denial(current_identity, sp, report_misconfiguration: false).nil?
    end
    @special_apps = SpecialAppCards::Base.for_identity(current_identity)
  end

  def welcome
    @return_to = params[:return_to]
    render layout: "logged_out"
  end

  def oauth_welcome
    # Extract client_id and login_hint from the return_to URL
    @return_to = params[:return_to]
    if @return_to.present?
      uri = URI.parse(@return_to)
      params_hash = URI.decode_www_form(uri.query || "").to_h
      client_id = params_hash["client_id"]
      @program = Program.find_by(uid: client_id) if client_id
      @login_hint = params_hash["login_hint"]
    end

    @program ||= nil
    render layout: "logged_out"
  end

  def external_api_docs
    render :external_api_docs, layout: "backend"
  end

  def security
  end

  def ruhq
    @person = Directory::Person.find_by(identity: current_identity)
    @hq_slugs = %w[hq hcb gap-years]
    @hq_collections = Directory::Collection.where(slug: @hq_slugs).index_by(&:slug)

    @memberships = {}
    if @person
      # find which of the target collections this person is an effective member of
      member_of = Directory::EffectiveMembership
        .where(person_id: @person.id, collection_id: @hq_collections.values.map(&:id))
        .pluck(:collection_id).to_set

      # the person's direct membership collection(s)
      direct_collection_ids = Directory::Membership.active
        .where(member_person: @person).pluck(:collection_id)

      @hq_collections.each do |slug, target|
        next unless member_of.include?(target.id)

        # walk from the person's direct group(s) up through the closure to the target
        # closure has (ancestor_id, descendant_id) — we want paths where
        # descendant is something the person is directly in, ancestor is the target
        chain_ids = Directory::Closure
          .where(ancestor_id: target.id, descendant_id: direct_collection_ids)
          .where.not(ancestor_id: target.id, descendant_id: target.id) # exclude self-loop unless direct
          .order(:depth).pluck(:descendant_id)

        if direct_collection_ids.include?(target.id)
          # direct member of the target itself
          @memberships[slug] = [ target.slug ]
        elsif chain_ids.any?
          # walk the chain: target → ... → person's direct group
          leaf = chain_ids.first
          path_ids = Directory::Closure
            .where(ancestor_id: target.id, descendant_id: leaf)
            .order(:depth).pluck(:descendant_id)
          # path_ids goes from shallowest to deepest: [target, mid, ..., leaf]
          # but target itself is depth 0 (self-loop), so it's already included
          chain = Directory::Collection.where(id: [ target.id ] + path_ids).index_by(&:id)
          @memberships[slug] = ([ target.id ] + path_ids).uniq.filter_map { |id| chain[id]&.slug }
        end
      end
    end
    render layout: "win98"
  end

  def slack_id = render layout: "minimal"

  def debug_dump
    if current_identity
      @ident = Identity
        .includes(:totps, :webauthn_credentials, :addresses, :email_change_requests, :verification_cases, :backend_user,
                  directory_person: { effective_memberships: :collection })
        .preload(:verifications) # not_ignored scope applied after load
        .find(current_identity.id)
      @dir_person = @ident.directory_person
      @ecrs = @ident.email_change_requests.sort_by(&:created_at).reverse.first(10)
      @verifications = @ident.verifications.select { |v| v.ignored_at.nil? }.sort_by(&:created_at).reverse.first(10)
      @vcases = @ident.verification_cases.sort_by(&:created_at).reverse.first(10)
      @addresses = @ident.addresses.sort_by(&:created_at).reverse
      @dir_memberships = @dir_person&.effective_memberships || []
    end
    render layout: "win98"
  end
end
