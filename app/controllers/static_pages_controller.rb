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
      @hq_collections.each do |slug, collection|
        em = Directory::EffectiveMembership.find_by(person_id: @person.id, collection_id: collection.id)
        next unless em

        # find the path: which direct memberships lead here?
        direct = Directory::Membership.active.where(member_person: @person)
          .includes(:collection).select { |m|
            Directory::EffectiveMembership.exists?(person_id: @person.id, collection_id: m.collection_id)
          }
        path_groups = direct.map(&:collection).select { |c|
          # is this collection an ancestor of the target?
          c.id == collection.id || Directory::Closure.exists?(ancestor_id: collection.id, descendant_id: c.id)
        }
        @memberships[slug] = path_groups
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
