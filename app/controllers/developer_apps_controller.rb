Fetching https://github.com/24c02/valid_email2.git
class DeveloperAppsController < ApplicationController
  before_action :require_developer_mode
  before_action :set_app, only: [ :show, :edit, :update, :destroy, :rotate_credentials ]

  def index
    @apps = current_identity.owned_developer_apps.order(created_at: :desc)
  end

  def show
  end

  def new
    @app = Program.new
  end

  def create
    @app = Program.new(app_params)
    @app.trust_level = :community_untrusted
    @app.owner_identity = current_identity

    if @app.save
      redirect_to developer_app_path(@app), notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @app.update(app_params)
      redirect_to developer_app_path(@app), notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    app_name = @app.name
    @app.create_activity :destroy, owner: current_identity, parameters: { name: app_name }
    @app.destroy
    redirect_to developer_apps_path, notice: t(".success"), status: :see_other
  end

  private

  def rotate_credentials
    @app.rotate_credentials!
    redirect_to developer_app_path(@app), notice: t(".success")
  end

  def require_developer_mode
    unless current_identity.developer_mode?
      flash[:error] = t(".require_developer_mode")
      redirect_to root_path
    end
  end

  def set_app
    @app = current_identity.owned_developer_apps.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = t("developer_apps.set_app.not_found")
    redirect_to developer_apps_path
  end

  def app_params
    params.require(:program).permit(:name, :redirect_uri, scopes_array: [])
  end
end
