module Backend
  class IdentitiesController < ApplicationController
    before_action :set_identity, except: [ :index ]

    def index
      authorize Identity

      if (search = params[:search])&.start_with? "ident!"
        ident = Identity.find_by_public_id(search)
        return redirect_to backend_identity_path ident if ident.present?
      end

      @identities = policy_scope(Identity)
        .search(search&.sub("mailto:", ""))
        .order(created_at: :desc)
        .page(params[:page])
        .per(25)
    end

    def show
      authorize @identity

      if current_user.super_admin? || current_user.manual_document_verifier?
        @available_scopes = [ "basic_info", "legal_name", "address" ]
      elsif current_user.organized_programs.any?
        organized_program_ids = current_user.organized_programs.pluck(:id)

        granted_tokens = @identity.access_tokens.where(application_id: organized_program_ids)

        @available_scopes = granted_tokens
          .map { |token| token.scopes }
          .flatten
          .uniq
          .reject(&:blank?)
      else
        @available_scopes = [ "basic_info" ]
      end

      @verifications = @identity.verifications.includes(:identity_document).order(created_at: :desc)

      @addresses = @identity.addresses.order(created_at: :desc)

      @all_programs = @identity.all_programs.distinct

      identity_activities = @identity.activities.includes(:owner)

      verification_activities = PublicActivity::Activity
        .where(trackable_type: "Verification", trackable_id: @identity.verifications.pluck(:id))
        .includes(:trackable, :owner)

      document_ids = @identity.documents.pluck(:id)
      break_glass_record_ids = BreakGlassRecord.where(break_glassable_type: "Identity::Document", break_glassable_id: document_ids).pluck(:id)
      break_glass_activities = PublicActivity::Activity
        .where(trackable_type: "BreakGlassRecord", trackable_id: break_glass_record_ids)
        .includes(:trackable, :owner)

      @activities = (identity_activities + verification_activities + break_glass_activities)
        .sort_by(&:created_at).reverse
    end

    def edit
      authorize @identity, :edit?
    end

    def update
      authorize @identity, :update?

      if params[:reason].blank?
        flash[:alert] = "Reason is required for identity updates"
        render :edit and return
      end

      if @identity.update(identity_params)
        @identity.create_activity(
          :admin_update,
          owner: current_user,
          parameters: {
            reason: params[:reason],
            changed_fields: @identity.previous_changes.except("updated_at").keys
          },
        )

        flash[:notice] = "Identity updated successfully"
        redirect_to backend_identity_path(@identity)
      else
        render :edit
      end
    end

    def clear_slack_id
      authorize @identity

      @identity.update!(slack_id: nil)
      @identity.create_activity(
        :clear_slack_id,
        owner: current_user,
      )
      flash[:notice] = "Slack ID cleared."
      redirect_to backend_identity_path(@identity)
    end

    def reprovision_slack
      authorize @identity

      scenario = OnboardingScenarios::DefaultJoin.new(@identity)
      slack_result = SCIMService.find_or_create_user(
        identity: @identity,
        scenario: scenario
      )

      if slack_result[:success]
        @identity.update(slack_id: slack_result[:slack_id])
        @identity.create_activity(
          :reprovision_slack,
          owner: current_user,
        )
        flash[:notice] = "Slack account provisioned: #{slack_result[:message]}"
      else
        flash[:error] = "Failed to provision Slack account: #{slack_result[:error]}"
      end

      redirect_to backend_identity_path(@identity)
    end

    def new_vouch
      authorize Verification::VouchVerification, :create?
      @vouch = @identity.vouch_verifications.build
    end

    def create_vouch
      authorize Verification::VouchVerification, :create?
      @vouch = @identity.vouch_verifications.build(vouch_params)
      if @vouch.save
        flash[:notice] = "Vouch verification created successfully"
        redirect_to backend_identity_path(@identity)
      else
        render :new_vouch
      end
    end

    def promote_to_full_user
      authorize @identity
      
      unless @identity.slack_id.present?
        flash[:error] = "Identity has no Slack account to promote"
        redirect_to backend_identity_path(@identity)
        return
      end

      if SlackService.promote_user(@identity.slack_id)
        @identity.create_activity(
          :promote_to_full_user,
          owner: current_user,
        )
        flash[:notice] = "Slack user promoted to full member"
      else
        flash[:error] = "Failed to promote Slack user"
      end
      
      redirect_to backend_identity_path(@identity)
    end

    private

    def set_identity
      @identity = policy_scope(Identity).find_by_public_id!(params[:id])
    end

    def identity_params
      params.require(:identity).permit(:first_name, :last_name, :legal_first_name, :legal_last_name, :primary_email, :phone_number, :birthday, :country, :hq_override, :ysws_eligible, :permabanned)
    end

    def vouch_params
      params.require(:verification_vouch_verification).permit(:evidence)
    end
  end
end
