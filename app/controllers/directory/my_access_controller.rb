# frozen_string_literal: true

module Directory
  class MyAccessController < BaseController
    skip_before_action :ensure_directory_access!
    helper_method :collection_link

    def show
      skip_authorization
      add_breadcrumb t("directory.my_access.show.title")

      @person = current_directory_person

      unless @person
        render "not_in_directory"
        return
      end

      @memberships = @person.memberships_with_via_path
      @app_exposures = @person.app_exposures
    end

    private

    # being a member doesn't mean you can open the collection's page
    def collection_link(collection)
      if policy(collection).show?
        helpers.link_to(collection.name, directory_collection_path(collection.slug))
      else
        collection.name
      end
    end

    def skip_authorization?
      action_name == "show"
    end
  end
end
