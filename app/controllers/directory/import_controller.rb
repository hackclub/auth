# frozen_string_literal: true

module Directory
  class ImportController < BaseController
    skip_after_action :verify_authorized

    before_action :require_admin!
    before_action :set_breadcrumbs

    def new
    end

    def preview
      csv_string = read_csv_from_params
      return if performed?
      unless csv_string
        redirect_to directory_new_import_path, alert: t("directory.import.no_file")
        return
      end

      @skip_effective_members = params[:skip_effective_members] == "1"
      @csv_string = csv_string
      @result = Directory::Import.call(csv_string:, dry_run: true, created_by: current_identity, skip_effective_members: @skip_effective_members)
    end

    def create
      csv_string = read_csv_from_params
      return if performed?
      unless csv_string
        redirect_to directory_new_import_path, alert: t("directory.import.no_file")
        return
      end

      result = Directory::Import.call(csv_string:, dry_run: false, created_by: current_identity, skip_effective_members: params[:skip_effective_members] == "1")

      if result.valid?
        redirect_to directory_root_path,
          notice: t("directory.import.success", created: result.created_count, skipped: result.skipped_count)
      else
        redirect_to directory_new_import_path,
          alert: t("directory.import.errors", count: result.errors.size)
      end
    end

    private

    def require_admin!
      raise ActionController::RoutingError, "Not Found" unless directory_admin?
    end

    def set_breadcrumbs
      add_breadcrumb(t("directory.import.breadcrumb"), directory_new_import_path)
    end

    def read_csv_from_params
      if params[:csv_file].present?
        return redirect_too_large if params[:csv_file].size > Directory::Import::MAX_CSV_BYTES
        params[:csv_file].read.force_encoding("UTF-8").scrub
      elsif (csv_text = params[:csv_text]).is_a?(String) && csv_text.present?
        return redirect_too_large if csv_text.bytesize > Directory::Import::MAX_CSV_BYTES
        csv_text
      end
    end

    def redirect_too_large
      redirect_to directory_new_import_path, alert: t("directory.import.file_too_large")
      nil
    end
  end
end
