class Backend::ProgramsController < Backend::ApplicationController
  before_action :set_program, only: [ :show, :edit, :update, :destroy ]

  hint :list_navigation, on: :index
  hint :back_navigation, on: :index

  def index
    authorize Program

    set_keyboard_shortcut(:back, backend_root_path)

    @programs = policy_scope(Program).includes(:identities).order(:name)
  end

  def show
    authorize @program
    @identities_count = @program.identities.distinct.count
  end

  def new
    @program = Program.new
    authorize @program
  end

  def create
    @program = Program.new(program_params)
    authorize @program

    if params[:oauth_application] && params[:oauth_application][:redirect_uri].present?
      @program.redirect_uri = params[:oauth_application][:redirect_uri]
    end

    if @program.save
      redirect_to backend_program_path(@program), notice: "Program was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @program
  end

  def update
    authorize @program

    if params[:oauth_application] && params[:oauth_application][:redirect_uri].present?
      @program.redirect_uri = params[:oauth_application][:redirect_uri]
    end

    if @program.update(program_params_for_user)
      redirect_to backend_program_path(@program), notice: "Program was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @program
    @program.destroy
    redirect_to backend_programs_path, notice: "Program was successfully deleted."
  end

  private

  def set_program
    @program = Program.find(params[:id])
  end

  def program_params
    params.require(:program).permit(:name, :description, :active, scopes_array: [])
  end

  def program_params_for_user
    permitted_params = [ :name, :redirect_uri ]

    if policy(@program).update_scopes?
      permitted_params += [ :description, :active, :trust_level, scopes_array: [] ]
    end

    params.require(:program).permit(permitted_params)
  end
end
