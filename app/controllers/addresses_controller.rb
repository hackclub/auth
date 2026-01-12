class AddressesController < ApplicationController
  include IsSneaky
  include AddressManagement
  include AhoyAnalytics

  before_action :set_address, only: [ :show, :edit, :update, :destroy, :make_primary ]
  before_action :hide_some_data_away, only: %i[program_create_address]

  def index
    @addresses = current_identity.addresses
    build_address

    if htmx_request? && params[:refresh_list]
      render_address_list
    end
  end

  def show
  end

  def new
    build_address
  end

  def create
    if create_address
      respond_to_create_success
    else
      respond_to_create_failure
    end
  end

  def program_create_address
    build_address
  end

  def edit
    if htmx_request?
      render partial: "addresses/edit_form", locals: { address: @address, portal: portal_context? }, layout: false
    end
  end

  def update
    if params[:make_primary] == "true"
      current_identity.update!(primary_address: @address)
      respond_to_make_primary
    elsif @address.update(address_params)
      if htmx_request?
        render_address_list
      else
        redirect_to addresses_path, notice: "address updated successfully!"
      end
    else
      if htmx_request?
        render partial: "addresses/edit_form", locals: { address: @address, portal: portal_context? }, layout: false
      else
        render :edit
      end
    end
  end

  def destroy
    can_destroy = current_identity.primary_address != @address

    if !can_destroy && Rails.env.development?
      current_identity.update(primary_address: nil)
      can_destroy = true
    end

    if can_destroy
      @address.destroy
      respond_to_destroy_success
    else
      respond_to_destroy_failure
    end
  end

  def make_primary
    current_identity.update(primary_address: @address)
    respond_to_make_primary
  end

  private

  def respond_to_create_success
    if htmx_request?
      render_address_list
    elsif params[:address][:from_program] == "true"
      redirect_to safe_redirect_url("address_return_to") || addresses_path, notice: "address created successfully!", allow_other_host: true
    else
      redirect_to addresses_path, notice: "address created successfully!"
    end
  end

  def respond_to_create_failure
    if htmx_request?
      render partial: "addresses/form", locals: { address: @address, url: addresses_path, htmx_target: htmx_target }, layout: false
    else
      render params[:address][:from_program] == "true" ? :program_create_address : :new
    end
  end

  def respond_to_destroy_success
    if htmx_request?
      render_address_list
    else
      redirect_to addresses_path, notice: "address deleted successfully!"
    end
  end

  def respond_to_destroy_failure
    if htmx_request?
      head :unprocessable_entity
    else
      flash[:alert] = "can't delete your primary address..."
      redirect_to addresses_path
    end
  end

  def respond_to_make_primary
    if htmx_request?
      render_address_list
    else
      redirect_to addresses_path, notice: "Primary address updated!"
    end
  end

  def render_address_list
    current_identity.reload
    @addresses = current_identity.addresses
    build_address
    target = portal_context? ? "#portal-addresses" : "#addresses-list"
    response.headers["HX-Retarget"] = target
    response.headers["HX-Reswap"] = "innerHTML"
    render partial: "addresses/address_list", locals: { addresses: @addresses, address: @address, portal: portal_context? }, layout: false
  end

  def htmx_request?
    request.headers["HX-Request"].present?
  end

  def htmx_target
    request.headers["HX-Target"]
  end

  def portal_context?
    ActiveModel::Type::Boolean.new.cast(params[:portal]) || request.headers["HX-Target"] == "#portal-addresses"
  end

  def set_address
    @address = current_identity.addresses.find(params[:id])
  end

  def address_params
    params.require(:address).permit(:first_name, :last_name, :line_1, :line_2, :city, :state, :postal_code, :country, :phone_number)
  end

  def create_address
    @address = current_identity.addresses.new(address_params)

    if @address.save
      track_event("address.created", country: @address.country, is_first: current_identity.addresses.count == 1)
      set_primary_if_needed
      true
    else
      false
    end
  end

  def set_primary_if_needed
    if current_identity.primary_address.nil? || current_identity.addresses.count == 1
      current_identity.update(primary_address: @address)
    end
  end
end
