class Verification::PersonaStudentIdVerification < Verification::PersonaVerification
  STUDENT_ID_COUNTRIES = %w[US CA AU].freeze

  TEMPLATES = [
    Template.new(:student_id, STUDENT_ID_COUNTRIES, {
      "name-first":    ->(i) { i.legal_first_name.presence || i.first_name },
      "name-last":     ->(i) { i.legal_last_name.presence || i.last_name }
    })
  ].freeze

  def document_type_label = "Student ID (Persona)"
  def auto_approvable? = true

  private

  def resolve_template
    TEMPLATES.first
  end

  def resolve_template_id
    Rails.application.credentials.persona.templates.student_id
  end
end
