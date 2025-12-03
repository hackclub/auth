module Backend
  class UsersController < ApplicationController
    before_action :set_user, except: [ :index, :new, :create ]

    hint :list_navigation, on: :index
    hint :search_focus, on: :index

    def index
      authorize Backend::User
      @users = User.all
      @users = @users.left_joins(:identity).where("identities.primary_email ILIKE :q OR identities.first_name ILIKE :q OR identities.last_name ILIKE :q OR users.username ILIKE :q", q: "%#{params[:search]}%") if params[:search].present?
      @users = @users.includes(:identity, :organized_programs)
    end

    def new
      authorize User
      @identities = if params[:query].present?
        Identity.search(params[:query]).where.not(id: User.linked.select(:identity_id)).limit(20)
      else
        Identity.none
      end
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

      unless params[:identity_id].present?
        redirect_to new_backend_user_path, alert: "No identity selected"
        return
      end
      identity = Identity.find(params[:identity_id])

      if User.exists?(identity_id: identity.id)
        redirect_to backend_users_path, alert: "This identity already has backend access!"
        return
      end

      @user = User.new(user_params.merge(
        identity: identity,
        username: "#{identity.first_name} #{identity.last_name}".strip,
        active: true
      ))

      if @user.save
        redirect_to backend_user_path(@user), notice: "Backend access granted to #{identity.primary_email}!"
      else
        redirect_to new_backend_user_path, alert: @user.errors.full_messages.join(", ")
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
  end
end
