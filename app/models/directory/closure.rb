module Directory
  class Closure < ApplicationRecord
    self.table_name = "directory_closure"
    self.primary_key = [:ancestor_id, :descendant_id]

    belongs_to :ancestor, class_name: "Directory::Collection"
    belongs_to :descendant, class_name: "Directory::Collection"

    def readonly? = true
  end
end
