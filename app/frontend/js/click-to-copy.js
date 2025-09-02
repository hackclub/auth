import $ from "jquery";

$('[data-copy-to-clipboard]').on('click', async function(e) {
    const element = e.currentTarget;
    const textToCopy = element.getAttribute('data-copy-to-clipboard');

    try {
        await navigator.clipboard.writeText(textToCopy);
        
        if (element.hasAttribute('aria-label')) {
            const previousLabel = element.getAttribute('aria-label');
            element.setAttribute('aria-label', 'copied!');
            
            setTimeout(() => {
                element.setAttribute('aria-label', previousLabel);
            }, 1000);
        }
    } catch (err) {
        console.error('Failed to copy text: ', err);
    }
});
