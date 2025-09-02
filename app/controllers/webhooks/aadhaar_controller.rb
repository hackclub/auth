module Webhooks
  class AadhaarController < ApplicationController
    def create
      Honeybadger.context({
        tags: "webhook, aadhaar"
      })

      unless params[:secret_key] == Rails.application.credentials.aadhaar.webhook_secret
        Honeybadger.notify("Aadhaar webhook: invalid secret key :-/")
        return render json: { error: "aw hell nah" }, status: :unauthorized
      end

      data = params[:response_data]
      unless data
        Honeybadger.notify("Aadhaar webhook: invalid data :-O")
        return render json: { error: "???" }, status: :unauthorized
      end

      data = Base64.decode64(data)
      data = JSON.parse(data, symbolize_names: true)

      raise "unknown digilocker status API status!" unless data[:status] == 1

      data[:data].each_pair do |tx_id, tx_data|
        aadhaar_verification = Verification::AadhaarVerification.find_by(aadhaar_external_transaction_id: tx_id)

        unless aadhaar_verification
          Honeybadger.notify("Aadhaar webhook: no verification found for tx_id #{tx_id}")
          next
        end

        if tx_data[:final_status] == "Denied"
          aadhaar_verification.mark_as_rejected!("service_unavailable", "Verification denied by Aadhaar service")
          next
        end

        unless tx_data[:final_status] == "Completed"
          Honeybadger.notify("Aadhaar webhook: verification #{tx_id} not completed")
          next
        end

        aadhaar_doc = tx_data[:msg].first { |doc| doc[:doc_type] == "ADHAR" }

        unless aadhaar_doc
          Honeybadger.notify("Aadhaar webhook: no Aadhaar document found for tx_id #{tx_id}???")
          next
        end

        aadhaar_data = aadhaar_doc[:data]

        aadhaar_verification.create_aadhaar_record!(
          identity: aadhaar_verification.identity,
          date_of_birth: Date.parse(aadhaar_data[:dob]),
          name: aadhaar_data[:name],
          raw_json_response: aadhaar_doc.to_json,
        )

        aadhaar_verification.create_activity(
          "data_received",
          owner: aadhaar_verification.identity,
        )

        aadhaar_verification.mark_pending!
      end

      render json: { message: "thanks!" }, status: :ok
    rescue StandardError => e
      raise
      Honeybadger.notify(e)
      render json: { error: "???" }, status: :internal_server_error
    end
  end
end
