class AddUniqueIndexToPersonaInquiryId < ActiveRecord::Migration[8.0]
  def change
    # persona_inquiry_id must be unique across verifications — if two
    # verifications claim the same inquiry, the webhook job (which does
    # find_by) silently picks one and orphans the other. a unique index
    # makes that structurally impossible.
    #
    # nulls are excluded: verifications without an inquiry (e.g. document
    # uploads, vouches) legitimately have nil here.
    remove_index :verifications, :persona_inquiry_id
    add_index :verifications, :persona_inquiry_id, unique: true, where: "persona_inquiry_id IS NOT NULL"
  end
end
