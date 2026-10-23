module Directory
  class Entitlement < Collection
    self.table_name = "directory_collections"

    def self.sti_name = "entitlement"
  end
end
