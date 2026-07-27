// live document capture for skip-persona manual verification cases.
// no file picker: the photo must come straight from the device camera.
document.addEventListener("DOMContentLoaded", () => {
  const el = document.querySelector("[data-camera-capture]");
  if (!el) return;

  const input = el.querySelector("[data-camera-input]");
  const video = el.querySelector("[data-camera-video]");
  const canvas = el.querySelector("[data-camera-canvas]");
  const message = el.querySelector("[data-camera-message]");
  const openBtn = el.querySelector("[data-camera-open]");
  const takeBtn = el.querySelector("[data-camera-take]");
  const retakeBtn = el.querySelector("[data-camera-retake]");
  const submitBtn = document.querySelector("[data-camera-submit]");

  let stream = null;

  const stopStream = () => {
    if (stream) stream.getTracks().forEach((track) => track.stop());
    stream = null;
  };

  const show = (elm, visible) => {
    if (elm) elm.style.display = visible ? "" : "none";
  };

  openBtn.addEventListener("click", async () => {
    if (!navigator.mediaDevices?.getUserMedia) {
      message.textContent = "This browser can't access a camera — open this page on your phone instead.";
      return;
    }
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment", width: { ideal: 1920 } },
        audio: false,
      });
    } catch (err) {
      console.error("[camera-capture]", err);
      message.textContent = "Camera access was blocked. Allow camera access and try again, or open this page on your phone.";
      return;
    }
    video.srcObject = stream;
    show(video, true);
    show(canvas, false);
    show(openBtn, false);
    show(takeBtn, true);
    show(retakeBtn, false);
    message.textContent = "Line your document up in the frame, then take the photo.";
  });

  takeBtn.addEventListener("click", () => {
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    canvas.getContext("2d").drawImage(video, 0, 0);
    canvas.toBlob(
      (blob) => {
        if (!blob) return;
        const file = new File([blob], "document-capture.jpg", { type: "image/jpeg" });
        const dataTransfer = new DataTransfer();
        dataTransfer.items.add(file);
        input.files = dataTransfer.files;
        stopStream();
        show(video, false);
        show(canvas, true);
        show(takeBtn, false);
        show(retakeBtn, true);
        if (submitBtn) submitBtn.disabled = false;
        message.textContent = "Looking good? If it's blurry or cut off, retake it.";
      },
      "image/jpeg",
      0.92
    );
  });

  retakeBtn.addEventListener("click", () => {
    input.value = "";
    if (submitBtn) submitBtn.disabled = true;
    openBtn.click();
  });

  window.addEventListener("pagehide", stopStream);
});
