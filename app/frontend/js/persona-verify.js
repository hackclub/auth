import Persona from "persona";

document.addEventListener("DOMContentLoaded", () => {
  const el = document.querySelector("[data-persona-verify]");
  if (!el) return;

  const { inquiryId, sessionToken, environmentId, host, statusUrl, fallbackUrl, msgComplete, msgCancel, msgError } = el.dataset;
  const button = el.querySelector("[data-persona-start]");
  const message = el.querySelector("[data-persona-message]");

  const client = new Persona.Client({
    inquiryId,
    sessionToken,
    environmentId,
    host,
    frameAncestors: [window.location.origin],
    onComplete: () => {
      if (message) message.textContent = msgComplete;
      window.location.href = statusUrl;
    },
    onCancel: () => {
      if (message) message.textContent = msgCancel;
    },
    onError: (error) => {
      console.error("[persona]", error);
      if (message && fallbackUrl) {
        message.innerHTML = `${msgError} <a href="${fallbackUrl}">Upload a document instead.</a>`;
      } else if (message) {
        message.textContent = msgError;
      }
    },
  });

  if (button) {
    button.addEventListener("click", () => client.open());
  }
});
