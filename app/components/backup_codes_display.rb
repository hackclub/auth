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
    style do
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

    style do
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
          onclick: safe("navigator.clipboard.writeText('#{@codes.join('\n')}').then(() => { this.textContent = '#{t('identity_backup_codes.copied')}'; setTimeout(() => this.textContent = '#{t('identity_backup_codes.copy_all')}', 2000); })")
        ) do
          t "identity_backup_codes.copy_all"
        end

        a(
          download: "backup-codes.txt",
          href: "data:text/plain;charset=utf-8,#{ERB::Util.url_encode(@codes.join("\n"))}",
          class: "button secondary"
        ) do
          t "identity_backup_codes.download"
        end

        button(
          type: "button",
          onclick: safe("window.print()"),
          class: "secondary"
        ) do
          t "identity_backup_codes.print"
        end
      end

      if @show_confirmation
        div(class: "backup-codes-confirmation") do
          label do
            input(type: "checkbox", id: "codes-saved-check", required: true)
            plain t("identity_backup_codes.confirmation_label")
          end

          render_block(@confirmation_button_block) if @confirmation_button_block
        end

        script do
          raw safe <<~JS
            (function() {
              const checkbox = document.getElementById('codes-saved-check');
              const finishBtn = document.getElementById('finish-setup-btn');
              if (checkbox && finishBtn) {
                checkbox.addEventListener('change', () => {
                  if (checkbox.checked) {
                    finishBtn.disabled = false;
                    finishBtn.style.pointerEvents = 'auto';
                    finishBtn.style.opacity = '1';
                    finishBtn.removeAttribute('data-disabled');
                  } else {
                    finishBtn.disabled = true;
                    finishBtn.style.pointerEvents = 'none';
                    finishBtn.style.opacity = '0.5';
                    finishBtn.setAttribute('data-disabled', 'true');
                  }
                });
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
