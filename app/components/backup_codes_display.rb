# frozen_string_literal: true

class Components::BackupCodesDisplay < Components::Base
  def initialize(codes:, warning_title:, warning_detail:, heading: nil, show_confirmation: false, header_block: nil, confirmation_button_block: nil)
    @codes = codes
    @warning_title = warning_title
    @warning_detail = warning_detail
    @heading = heading
    @show_confirmation = show_confirmation
    @header_block = header_block
    @confirmation_button_block = confirmation_button_block
  end

  def view_template(&block)
    style do
      raw safe <<~CSS
        @media print {
          body > *,
          nav, header, footer, aside,
          .sidebar, .nav, .navigation {
            visibility: hidden !important;
          }
          
          .backup-codes-section,
          .backup-codes-section *,
          .backup-codes-display,
          .backup-codes-display * {
            visibility: visible !important;
          }
          
          .backup-codes-actions,
          .backup-codes-confirmation {
            display: none !important;
          }
          
          .backup-codes-display {
            position: absolute;
            left: 0;
            top: 0;
            width: 100%;
            margin: 0 !important;
            padding: 20pt !important;
          }
          
          .totp-setup-header {
            margin-bottom: 20pt !important;
          }
          
          .totp-setup-header h3 {
            font-size: 18pt !important;
          }
          
          .backup-codes-display h4 {
            font-size: 18pt !important;
            margin-bottom: 20pt !important;
          }
          
          .codes-grid {
            background: white !important;
            border: 1px solid #000 !important;
            page-break-inside: avoid;
          }
          
          .backup-code {
            background: white !important;
            border: 1px solid #000 !important;
            color: #000 !important;
          }
        }
      CSS
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
