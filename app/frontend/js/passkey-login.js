export function passkeyLogin() {
    return {
        loading: false,
        error: null,
        browserSupported: true,

        init() {
            this.browserSupported = !!(
                globalThis.PublicKeyCredential?.parseRequestOptionsFromJSON &&
                navigator.credentials?.get
            );
        },

        async login() {
            this.loading = true;
            this.error = null;

            try {
                const response = await fetch('/passkey/login/options', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                    }
                });

                if (!response.ok) {
                    throw new Error('Failed to get authentication options from server');
                }

                const contentType = response.headers.get('content-type') || '';
                if (!contentType.includes('application/json')) {
                    window.location.href = response.url;
                    return;
                }

                const options = await response.json();
                const publicKey = PublicKeyCredential.parseRequestOptionsFromJSON(options);
                const credential = await navigator.credentials.get({ publicKey });

                if (!credential) {
                    throw new Error('Authentication failed - no credential returned');
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
                        authenticatorData: toBase64Url(responseData.authenticatorData),
                        signature: toBase64Url(responseData.signature),
                        userHandle: responseData.userHandle ? toBase64Url(responseData.userHandle) : null,
                    },
                    clientExtensionResults: credential.getClientExtensionResults(),
                };

                const credentialDataField = document.getElementById('passkey-login-credential-data');
                const form = document.getElementById('passkey-login-form');

                if (!credentialDataField || !form) {
                    throw new Error('Form elements not found');
                }

                credentialDataField.value = JSON.stringify(credentialJSON);
                form.submit();
            } catch (error) {
                console.error('Passkey login error:', error);

                if (error.name === 'NotAllowedError') {
                    this.error = 'Sign in was cancelled or not allowed';
                } else if (error.name === 'InvalidStateError') {
                    this.error = 'No passkey found for this account';
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