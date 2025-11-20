module Backend
  class UsersController < ApplicationController
    before_action :set_user, except: [ :index, :new, :create ]

    def index
      authorize Backend::User
      @users = User.all
    end

    def new
      authorize User
      @user = User.new
    end

    def edit
      authorize @user
    end

    def update
      authorize @user
      @user.update!(user_params)
      redirect_to backend_users_path, notice: "User updated!"
    rescue => e
      redirect_to backend_users_path, alert: e.message
    end

    def create
      authorize User
      @user = User.new(new_user_params.merge(active: true))
      
      if @user.slack_id.present?
        identity = Identity.find_by(slack_id: @user.slack_id)
        if identity
          @user.identity = identity
        else
          flash.now[:warning] = "No Identity found with Slack ID #{@user.slack_id}. User will not be able to log in until linked."
        end
      end

      if @user.save
        redirect_to backend_users_path, notice: "User created!"
      else
        render :new
      end
    end

    def show
      authorize @user
    end

    def activate
      authorize @user
      @user.activate!
      flash[:success] = "User activated!"
      redirect_to @user
    end

    def deactivate
      authorize @user
      if @user == current_user
        flash[:warning] = "i'm not sure that's a great idea..."
        return redirect_to @user
      end
      @user.deactivate!
      flash[:success] = "User deactivated."
      redirect_to @user
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:backend_user).permit(:username, :icon_url, :all_fields_access, :human_endorser, :program_manager, :manual_document_verifier, :super_admin, organized_program_ids: [])
    end

    def new_user_params
      params.require(:backend_user).permit(:slack_id, :username, :all_fields_access, :human_endorser, :program_manager, :manual_document_verifier, :super_admin, organized_program_ids: [])
    end
  end
end
