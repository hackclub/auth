class DeveloperAppsController < ApplicationController
  include IdentityAuthorizable

  before_action :set_app, only: [ :show, :edit, :update, :destroy, :rotate_credentials, :revoke_all_authorizations, :activity_log ]

  def index
    authorize Program

    @apps = policy_scope(Program).includes(:owner_identity).order(created_at: :desc)

    if admin?
      @apps = @apps.where(
        "oauth_applications.name ILIKE :q OR oauth_applications.uid = :uid",
        q: "%#{params[:search]}%",
        uid: params[:search]
      )
    end

    @apps = @apps.page(params[:page]).per(25)

    @pending_invitations = current_identity.pending_collaboration_invitations
  end

  def show
    authorize @app
    @identities_count = @app.identities.distinct.count
    if policy(@app).manage_collaborators?
      @collaborators = @app.program_collaborators.accepted.includes(:identity)
      @pending_invitations_for_app = @app.program_collaborators.pending
    end
  end

  def activity_log
    authorize @app
    @activities = PublicActivity::Activity
      .where(trackable: @app)
      .includes(:owner)
      .order(created_at: :desc)
      .limit(50)
      .to_a

    # Preload backend_user through the polymorphic owner to avoid N+1 in IdentityMention
    identities = @activities.filter_map { |a| a.owner if a.owner_type == "Identity" }
    ActiveRecord::Associations::Preloader.new(records: identities, associations: :backend_user).call if identities.any?

    render layout: "htmx"
  end

  def new
    @app = Program.new(trust_level: :community_untrusted)
    authorize @app
  end

  def create
    @app = Program.new(app_params_for_identity)
    authorize @app

    unless policy(@app).update_trust_level?
      @app.trust_level = :community_untrusted
    end
    @app.owner_identity = current_identity

    # Server-side scope enforcement: only allow scopes within this user's tier
    enforce_allowed_scopes!(@app, existing_scopes: [])

    if @app.save
      redirect_to developer_app_path(@app), notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @app
  end

  def update
    authorize @app

    snapshot = @app.audit_snapshot
    existing_scopes = @app.scopes_array.dup
    @app.assign_attributes(app_params_for_identity)

    # Server-side scope enforcement: preserve locked scopes, reject unauthorized additions
    enforce_allowed_scopes!(@app, existing_scopes: existing_scopes)

    if @app.save
      changes = @app.audit_diff(snapshot)
      if changes.any?
        @app.create_activity :change, owner: current_identity, parameters: { changes: changes }
      end
      redirect_to developer_app_path(@app), notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @app
    app_name = @app.name
    @app.create_activity :destroy, owner: current_identity, parameters: { name: app_name }
    @app.destroy
    redirect_to developer_apps_path, notice: t(".success"), status: :see_other
  end

  def rotate_credentials
    authorize @app
    @app.rotate_credentials!
    @app.create_activity :rotate_credentials, owner: current_identity
    redirect_to developer_app_path(@app), notice: t(".success")
  end

  def revoke_all_authorizations
    authorize @app
    count = @app.access_tokens.update_all(revoked_at: Time.current)
    PaperTrail.request.whodunnit = current_identity.id.to_s
    @app.paper_trail_event = "revoke_all_authorizations"
    @app.paper_trail.save_with_version
    @app.create_activity :revoke_all_authorizations, owner: current_identity, parameters: { count: count }
    redirect_to developer_app_path(@app), notice: t(".success", count: count)
  end

  private

  def set_app
    @app = Program.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = t("developer_apps.set_app.not_found")
    redirect_to developer_apps_path
  end

  # Server-side enforcement: a user can only add/remove scopes within their
  # allowed tier.  Scopes outside that tier that already exist on the app
  # ("locked scopes") are always preserved — a community user editing an
  # hq_official app cannot strip `basic_info`, and nobody can inject
  # `set_slack_id` via a forged form.
  #
  # Formula:  final = (submitted ∩ allowed) ∪ (existing ∩ ¬allowed)
  def enforce_allowed_scopes!(app, existing_scopes:)
    allowed   = policy(app).allowed_scopes
    submitted = app.scopes_array

    user_controlled = submitted & allowed        # only keep what they're allowed to touch
    locked          = existing_scopes - allowed  # preserve what they can't touch

    app.scopes_array = (user_controlled + locked).uniq
  end

  def app_params_for_identity
    permitted = [ :name, :redirect_uri, scopes_array: [] ]

    if policy(@app || Program.new).update_trust_level?
      permitted << :trust_level
    end

    if policy(@app || Program.new).update_onboarding_scenario?
      permitted << :onboarding_scenario
    end

    if policy(@app || Program.new).update_active?
      permitted << :active
    end

    params.require(:program).permit(permitted)
  end

  def admin?
    backend_user = current_identity.backend_user
    backend_user&.program_manager? || backend_user&.super_admin?
  end
  helper_method :admin?
end
