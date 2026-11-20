# frozen_string_literal: true

module Backend
  class SAMLCertificatesController < ApplicationController
    before_action :set_certificate, only: [ :show, :promote, :retire ]

    def index
      authorize SAMLCertificate
      @certificates = SAMLCertificate.order(
        Arel.sql("CASE role WHEN 'signing' THEN 0 WHEN 'rollover' THEN 1 ELSE 2 END, created_at DESC")
      )
      add_breadcrumb "saml certificates", backend_saml_certificates_path
    end

    def show
      authorize @certificate
      add_breadcrumb "saml certificates", backend_saml_certificates_path
      add_breadcrumb @certificate.fingerprint.first(8)
    end

    def new
      authorize SAMLCertificate
      add_breadcrumb "saml certificates", backend_saml_certificates_path
      add_breadcrumb "generate"
    end

    # user-facing failures only (guards, invalid transitions, validations); anything else
    # (Pundit, Errno, OpenSSL, DB) propagates to rescue_from so it reaches Sentry
    ROTATION_ERRORS = [ RuntimeError, ArgumentError, ActiveRecord::RecordInvalid ].freeze

    def create
      authorize SAMLCertificate

      cn = params[:cn].presence || SAMLCertificate::DEFAULT_CN
      validity_years = Integer(params[:validity_years].presence || 1, exception: false)

      @certificate = SAMLCertificate.generate!(cn:, validity_years:)
      @certificate.create_activity :generate, owner: current_user
      redirect_to backend_saml_certificate_path(@certificate), notice: "#{@certificate.role} cert generated — key at #{@certificate.key_path}"
    rescue *ROTATION_ERRORS => e
      redirect_to new_backend_saml_certificate_path, alert: e.message
    end

    def promote
      authorize @certificate
      @certificate.promote!
      @certificate.create_activity :promote, owner: current_user
      redirect_to backend_saml_certificates_path, notice: "promoted — update SPs now. old cert is rollover: promote it to roll back, retire it when SPs are done"
    rescue *ROTATION_ERRORS => e
      redirect_to backend_saml_certificate_path(@certificate), alert: e.message
    end

    def retire
      authorize @certificate
      @certificate.retire!
      @certificate.create_activity :retire, owner: current_user
      redirect_to backend_saml_certificates_path, notice: "retired"
    rescue *ROTATION_ERRORS => e
      redirect_to backend_saml_certificate_path(@certificate), alert: e.message
    end

    private

    def set_certificate
      @certificate = SAMLCertificate.find(params[:id])
    end
  end
end
