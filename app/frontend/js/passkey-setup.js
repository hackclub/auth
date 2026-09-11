export function passkeySetup() {
    return {
        loading: false,
        error: null,
        dontShowAgain: false,
        browserSupported: true,

        init() {
            this.browserSupported = !!(
                globalThis.PublicKeyCredential?.parseCreationOptionsFromJSON &&
                navigator.credentials?.create
            );

            if (!this.browserSupported) {
                const params = new URLSearchParams(window.location.search);
                const returnTo = params.get('return_to');
                window.location.href = returnTo && returnTo.startsWith('/') ? returnTo : '/';
            }
        },

        async setup() {
            this.loading = true;
            this.error = null;

            try {
                const params = new URLSearchParams(window.location.search);
                const returnTo = params.get('return_to');
                const url = returnTo ? `/passkeys/options?return_to=${encodeURIComponent(returnTo)}` : '/passkeys/options';
                const response = await fetch(url, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                    }
                });

                if (!response.ok) {
                    throw new Error('Failed to get registration options from server');
                }

                const contentType = response.headers.get('content-type') || '';
                if (!contentType.includes('application/json')) {
                    window.location.href = response.url;
                    return;
                }

                const options = await response.json();
                const publicKey = PublicKeyCredential.parseCreationOptionsFromJSON(options);
                const credential = await navigator.credentials.create({ publicKey });

                if (!credential) {
                    throw new Error('Credential creation failed');
                }

                const responseData = credential.response;
                const toBase64Url = (buffer) => {
                    return btoa(String.fromCharCode(...new Uint8Array(buffer)))
                        .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
                };
                const credentialJSON = {
                    id: credential.id,
                    rawId: toBase64Url(credential.rawId),
                    type: credential.type,
                    response: {
                        clientDataJSON: toBase64Url(responseData.clientDataJSON),
                        attestationObject: toBase64Url(responseData.attestationObject),
                    },
                    clientExtensionResults: credential.getClientExtensionResults(),
                };

                const credentialDataField = document.getElementById('setup-credential-data');
                const form = document.getElementById('setup-registration-form');

                if (!credentialDataField || !form) {
                    throw new Error('Form elements not found');
                }

                credentialDataField.value = JSON.stringify(credentialJSON);
                form.submit();
            } catch (error) {
                console.error('Passkey setup error:', error);

                if (error.name === 'NotAllowedError') {
                    this.error = 'Setup was cancelled or not allowed';
                } else if (error.name === 'InvalidStateError') {
                    this.error = 'This passkey is already registered';
                } else if (error.name === 'NotSupportedError') {
                    this.error = 'Passkeys are not supported on this device';
                } else {
                    this.error = error.message || 'An unexpected error occurred';
                }

                this.loading = false;
            }
        }
    };
}