# frozen_string_literal: true

module Directory
  class MyAccessController < BaseController
    def show
      skip_authorization
      add_breadcrumb t("directory.my_access.show.title")

      @person = current_directory_person

      unless @person
        render "not_in_directory"
        return
      end

      @memberships = @person.memberships_with_via_path
    end

    private

    def skip_authorization?
      action_name == "show"
    end
  end
end
