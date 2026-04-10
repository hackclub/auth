class Persona::MockAPIService
  def create_inquiry(template_id:, account_reference_id:)
    inquiry_id = "inq_test_#{SecureRandom.hex(8)}"

    ver_id = "ver_gov_test_#{SecureRandom.hex(8)}"

    Persona::Inquiry.new(
      id: inquiry_id,
      status: "created",
      account_id: "act_test_#{Digest::SHA256.hexdigest(account_reference_id)[0..11]}",
      session_token: "session_tok_#{SecureRandom.hex(16)}",
      verification_ids: [{ type: "verification/government-id", id: ver_id }]
    )
  end

  def retrieve_inquiry(inquiry_id)
    Persona::Inquiry.new(
      id: inquiry_id,
      status: "completed",
      account_id: "act_test_mock",
      session_token: nil,
      verification_ids: [{ type: "verification/government-id", id: "ver_gov_#{inquiry_id.delete_prefix('inq_')}" }]
    )
  end

  def resume_inquiry(inquiry_id)
    Persona::Inquiry.new(
      id: inquiry_id,
      status: "pending",
      account_id: "act_test_mock",
      session_token: "session_tok_#{SecureRandom.hex(16)}",
      verification_ids: []
    )
  end

  def retrieve_government_id_verification(_verification_id)
    Persona::GovernmentIdVerification.new(
      id: "ver_test_#{SecureRandom.hex(8)}",
      status: "passed",
      name_first: "HEIDI",
      name_last: "TRASHWORTH",
      birthdate: Date.parse("2008-06-15"),
      country_code: "US",
      front_photo: { filename: "front.jpg", url: "https://files.withpersona.com/front.jpg?access_token=mock", byte_size: 12345 },
      back_photo: { filename: "back.jpg", url: "https://files.withpersona.com/back.jpg?access_token=mock", byte_size: 12345 },
      selfie_photo: nil
    )
  end

  def download_file(_file_id)
    StringIO.new("mock image data for testing")
  end
end
