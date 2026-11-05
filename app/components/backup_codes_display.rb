# frozen_string_literal: true

class Components::BackupCodesDisplay < Components::Base
  def initialize(codes:, warning_title:, warning_detail:, heading: nil, show_confirmation: false, header_block: nil, confirmation_button_block: nil, identity: nil)
    @codes = codes
    @warning_title = warning_title
    @warning_detail = warning_detail
    @heading = heading
    @show_confirmation = show_confirmation
    @header_block = header_block
    @confirmation_button_block = confirmation_button_block
    @identity = identity
  end

  def view_template(&block)
    style(nonce: helpers.content_security_policy_nonce) do
      raw safe <<~CSS
        @media print {
          @page {
            margin: 1cm;
            size: A4;
          }
        #{'  '}
          html, body {
            height: 100vh !important;
            max-height: 100vh !important;
            overflow: hidden !important;
          }
        #{'  '}
          body {
            margin: 0 !important;
            padding: 0 !important;
          }
        #{'  '}
          body::after {
            content: none !important;
            display: none !important;
          }
        #{'  '}
          body * {
            visibility: hidden !important;
          }
        #{'  '}
          .backup-codes-display,
          .backup-codes-display * {
            visibility: visible !important;
          }
        #{'  '}
          .backup-codes-actions,
          .backup-codes-confirmation,
          .banner {
            display: none !important;
          }
        #{'  '}
          .print-only-banner {
            display: block !important;
            font-size: 10pt !important;
            padding: 6pt 8pt !important;
            margin: 0 0 12pt !important;
            border: 1px solid #000 !important;
            background: white !important;
          }
        #{'  '}
          .backup-codes-display {
            position: absolute !important;
            top: 0 !important;
            left: 0 !important;
            width: 100% !important;
            margin: 0 !important;
            padding: 0 !important;
            break-inside: avoid-page;
            page-break-inside: avoid;
          }
        #{'  '}
          .totp-setup-header {
            margin-bottom: 12pt !important;
          }
        #{'  '}
          .totp-setup-header h3 {
            font-size: 14pt !important;
            margin: 0 0 4pt !important;
          }
        #{'  '}
          .totp-setup-header .step-indicator {
            font-size: 10pt !important;
          }
        #{'  '}
          .backup-codes-display h4 {
            font-size: 12pt !important;
            margin: 0 0 8pt !important;
          }
        #{'  '}
          .codes-grid {
            background: white !important;
            border: 1px solid #000 !important;
            page-break-inside: avoid;
            break-inside: avoid-page;
            padding: 8pt !important;
            gap: 6pt !important;
            margin: 0 !important;
          }
        #{'  '}
          .backup-code {
            background: white !important;
            border: 1px solid #000 !important;
            color: #000 !important;
            font-size: 10pt !important;
            padding: 4pt !important;
          }
        }
      CSS
    end

    style(nonce: helpers.content_security_policy_nonce) do
      raw safe ".print-only-banner { display: none; }"
    end

    div(class: "backup-codes-display") do
      if @heading && @header_block
        div(class: "totp-setup-header") do
          render_block(@header_block)
        end
      end

      render Components::Banner.new(kind: :warning) do
        b { @warning_title }
        br
        plain @warning_detail
      end

      div(class: "print-only-banner") do
        if @identity
          b { "Hack Club Auth recovery codes for " }
          plain @identity&.primary_email
          br
          i { "Generated on #{Time.current.strftime('%B %d, %Y at %I:%M %p %Z')}" }
        end
      end

      div(class: "codes-grid") do
        @codes.each do |code|
          code(class: "backup-code") { code }
        end
      end

      div(class: "backup-codes-actions") do
        button(
          type: "button",
          data_action: "copy-codes",
          data_codes: @codes.join("\n"),
          data_label_copied: t("identity_backup_codes.copied"),
          data_label_default: t("identity_backup_codes.copy_all")
        ) do
          t "identity_backup_codes.copy_all"
        end

        a(
          download: "backup-codes.txt",
          href: "data:text/plain;charset=utf-8,#{ERB::Util.url_encode(@codes.join("\n"))}",
          role: "button",
          class: "secondary"
        ) do
          t "identity_backup_codes.download"
        end

        button(
          type: "button",
          data_action: "print-page",
          class: "secondary"
        ) do
          t "identity_backup_codes.print"
        end
      end

      script(nonce: helpers.content_security_policy_nonce) do
        raw safe <<~JS
          document.querySelectorAll('[data-action="copy-codes"]').forEach(function(btn) {
            btn.addEventListener('click', function() {
              var codes = btn.dataset.codes;
              navigator.clipboard.writeText(codes);
              var original = btn.textContent;
              btn.textContent = btn.dataset.labelCopied;
              setTimeout(function() { btn.textContent = btn.dataset.labelDefault; }, 2000);
            });
          });
          document.querySelectorAll('[data-action="print-page"]').forEach(function(btn) {
            btn.addEventListener('click', function() { window.print(); });
          });
        JS
      end

      if @show_confirmation
        div(class: "backup-codes-confirmation") do
          label do
            input(type: "checkbox", id: "codes-saved-check", required: true)
            plain t("identity_backup_codes.confirmation_label")
          end

          render_block(@confirmation_button_block) if @confirmation_button_block
        end

        script(nonce: helpers.content_security_policy_nonce) do
          raw safe <<~JS
            (function() {
              var cb = document.getElementById('codes-saved-check');
              var btn = cb && cb.closest('.backup-codes-confirmation').querySelector('input[type=submit], button[type=submit]');
              if (cb && btn) {
                btn.disabled = !cb.checked;
                cb.addEventListener('change', function() { btn.disabled = !cb.checked; });
              }
            })();
          JS
        end
      end
    end
  end

  private

  def render_block(block)
    if block.is_a?(Proc)
      raw safe block.call
    end
  end
end
