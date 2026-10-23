module Directory
  class Group < Collection
    self.table_name = "directory_collections"

    def self.sti_name = "group"
  end
end
