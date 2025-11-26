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

    toBase64url(buffer) {
        const base64 = btoa(String.fromCharCode(...new Uint8Array(buffer)));
        return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    },

    async getRegistrationOptions(nickname) {
        const userId = new Uint8Array(16);
        crypto.getRandomValues(userId);

        const challenge = new Uint8Array(32);
        crypto.getRandomValues(challenge);

        return {
            challenge: this.toBase64url(challenge),
            rp: {
                name: "Hack Club Account",
                id: window.location.hostname
            },
            user: {
                id: this.toBase64url(userId),
                name: "user@example.com",
                displayName: nickname
            },
            pubKeyCredParams: [
                { type: "public-key", alg: -7 },
                { type: "public-key", alg: -257 }
            ],
            authenticatorSelection: {
                authenticatorAttachment: "platform",
                requireResidentKey: false,
                residentKey: "preferred",
                userVerification: "preferred"
            },
            timeout: 60000,
            attestation: "none"
        };
    },

    async register(nickname) {
        try {
            const options = await this.getRegistrationOptions(nickname);
            console.log('Registration options:', options);

            const publicKey = PublicKeyCredential.parseCreationOptionsFromJSON(options);
            console.log('Parsed creation options:', publicKey);

            const credential = await navigator.credentials.create({ publicKey });

            if (!credential) {
                throw new Error('Credential creation failed');
            }

            console.log('Credential created:', credential);

            const credentialJSON = credential.toJSON();
            console.log('Credential JSON:', credentialJSON);

            const registrationData = {
                nickname: nickname,
                credential: credentialJSON,
                timestamp: new Date().toISOString()
            };

            console.log('Registration data:', registrationData);

            return {
                success: true,
                data: registrationData
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
            successAlert.style.display = 'block';
            nicknameInput.value = '';
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

        // Find the form within the passkey registration container
        const container = document.getElementById('passkey-registration-container');
        const form = container?.querySelector('form');
        if (form && !form.dataset.webauthnInitialized) {
            form.addEventListener('submit', (e) => this.handleSubmit(e));
            form.dataset.webauthnInitialized = 'true';
        }
    }
};

export { registerWebauthn };
