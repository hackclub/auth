module AadhaarService
  class Mock
    def generate_step_1_link(callback_url:, redirect_url:, trans_id:)
      sleep Random.random_number(2..7)
      {
        status: 1,
        msg: "youuuuuuu",
        ts_trans_id: "mrow_mrrp_external_of_#{trans_id}",
        data: {
          url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        }
      }
    end
  end
end
