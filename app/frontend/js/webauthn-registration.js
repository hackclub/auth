const registerWebauthn = {
    checkBrowserSupport() {
        const hasJsonSupport = !!globalThis.PublicKeyCredential?.parseCreationOptionsFromJSON;

        if (!hasJsonSupport) {
            this.showBrowserWarning();
            return false;
        }

        return true;
    },

    showBrowserWarning() {
        const warning = document.getElementById('browser-support-warning');
        const formContainer = document.querySelector('.passkey-setup');

        if (warning) warning.style.display = 'block';
        if (formContainer) formContainer.style.display = 'none';
    },

    async getRegistrationOptions() {
        // Fetch registration options from the server
        // The server will generate a cryptographic challenge and return user info
        const response = await fetch('/identity_webauthn_credentials/options', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
            }
        });

        if (!response.ok) {
            throw new Error('Failed to get registration options from server');
        }

        return await response.json();
    },

    async register(nickname) {
        try {
            // Get registration options from server (includes challenge and user info)
            const options = await this.getRegistrationOptions();
            console.log('Registration options:', options);

            // Parse the options and create the credential
            const publicKey = PublicKeyCredential.parseCreationOptionsFromJSON(options);
            console.log('Parsed creation options:', publicKey);

            const credential = await navigator.credentials.create({ publicKey });

            if (!credential) {
                throw new Error('Credential creation failed');
            }

            console.log('Credential created:', credential);

            const credentialJSON = credential.toJSON();
            console.log('Credential JSON:', credentialJSON);

            const response = await fetch('/identity_webauthn_credentials', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                },
                body: JSON.stringify({
                    nickname: nickname,
                    ...credentialJSON
                })
            });

            const result = await response.json();

            if (!response.ok || !result.success) {
                throw new Error(result.error || 'Failed to register passkey');
            }

            console.log('Registration successful:', result);

            return {
                success: true,
                data: result
            };
        } catch (error) {
            console.error('Passkey registration error:', error);

            let errorMessage = 'An unexpected error occurred';

            if (error.name === 'NotAllowedError') {
                errorMessage = 'Registration was cancelled or not allowed';
            } else if (error.name === 'InvalidStateError') {
                errorMessage = 'This passkey is already registered';
            } else if (error.name === 'NotSupportedError') {
                errorMessage = 'Passkeys are not supported on this device';
            } else if (error.message) {
                errorMessage = error.message;
            }

            return {
                success: false,
                error: errorMessage
            };
        }
    },

    async handleSubmit(event) {
        event.preventDefault();

        const nicknameInput = document.getElementById('webauthn-nickname');
        const registerBtn = document.getElementById('register-btn');
        const btnText = registerBtn?.querySelector('.btn-text');
        const btnSpinner = registerBtn?.querySelector('.btn-spinner');
        const successAlert = document.getElementById('webauthn-registration-success');
        const errorAlert = document.getElementById('webauthn-registration-error');
        const errorMessage = document.getElementById('error-message');

        const nickname = nicknameInput.value.trim();
        if (!nickname) {
            this.showError('Please enter a nickname for your passkey');
            return;
        }

        registerBtn.disabled = true;
        btnText.style.display = 'none';
        btnSpinner.style.display = 'inline';
        successAlert.style.display = 'none';
        errorAlert.style.display = 'none';

        const result = await this.register(nickname);

        registerBtn.disabled = false;
        btnText.style.display = 'inline';
        btnSpinner.style.display = 'none';

        if (result.success) {
            // Redirect to the URL provided by the server (flash message will be displayed)
            window.location.href = result.data.redirect_url || '/identity_webauthn_credentials';
        } else {
            errorMessage.textContent = result.error;
            errorAlert.style.display = 'block';
        }
    },

    showError(message) {
        const errorAlert = document.getElementById('webauthn-registration-error');
        const errorMessage = document.getElementById('error-message');

        if (errorMessage) errorMessage.textContent = message;
        if (errorAlert) errorAlert.style.display = 'block';
    },

    init() {
        if (!this.checkBrowserSupport()) {
            return;
        }

        const container = document.getElementById('passkey-registration-container');
        const form = container?.querySelector('form');
        if (form && !form.dataset.webauthnInitialized) {
            form.addEventListener('submit', (e) => this.handleSubmit(e));
            form.dataset.webauthnInitialized = 'true';
        }
    }
};

export { registerWebauthn };
