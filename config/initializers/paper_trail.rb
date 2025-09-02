class PaperTrail::Version
  def responsible_party
    return nil unless whodunnit.present?
    if whodunnit&.start_with? "Backend user: "
      uid = whodunnit[14..]
      return nil unless uid.present?
      Backend::User.find_by(id: uid)
    else
      Identity.find_by(id: whodunnit)
    end
  end
end
