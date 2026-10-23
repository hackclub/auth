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
      unless csv_string
        redirect_to directory_new_import_path, alert: t("directory.import.no_file")
        return
      end

      @csv_string = csv_string
      @result = Directory::Import.call(csv_string:, dry_run: true, created_by: current_identity)
    end

    def create
      csv_string = read_csv_from_params
      unless csv_string
        redirect_to directory_new_import_path, alert: t("directory.import.no_file")
        return
      end

      result = Directory::Import.call(csv_string:, dry_run: false, created_by: current_identity)

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
        params[:csv_file].read.force_encoding("UTF-8")
      elsif params[:csv_text].present?
        params[:csv_text]
      end
    end
  end
end
