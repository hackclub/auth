// live capture for skip-persona manual verification cases — the document
// photo and the selfie both come straight from the device camera, no file
// picker. supports multiple widgets per page; submit unlocks only once
// every widget has a capture.
document.addEventListener("DOMContentLoaded", () => {
  const widgets = Array.from(document.querySelectorAll("[data-camera-capture]"));
  if (!widgets.length) return;

  const submitBtn = document.querySelector("[data-camera-submit]");

  const updateSubmit = () => {
    if (!submitBtn) return;
    submitBtn.disabled = !widgets.every(
      (widget) => widget.querySelector("[data-camera-input]").files.length > 0
    );
  };

  widgets.forEach((el) => {
    const input = el.querySelector("[data-camera-input]");
    const video = el.querySelector("[data-camera-video]");
    const canvas = el.querySelector("[data-camera-canvas]");
    const message = el.querySelector("[data-camera-message]");
    const openBtn = el.querySelector("[data-camera-open]");
    const takeBtn = el.querySelector("[data-camera-take]");
    const retakeBtn = el.querySelector("[data-camera-retake]");
    const facingMode = el.dataset.cameraFacing || "environment";
    const filename = el.dataset.cameraFilename || "capture.jpg";

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
          video: { facingMode, width: { ideal: 1920 } },
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
      message.textContent =
        facingMode === "user"
          ? "Look at the camera, then take the photo."
          : "Line your document up in the frame, then take the photo.";
    });

    takeBtn.addEventListener("click", () => {
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      canvas.getContext("2d").drawImage(video, 0, 0);
      canvas.toBlob(
        (blob) => {
          if (!blob) return;
          const file = new File([blob], filename, { type: "image/jpeg" });
          const dataTransfer = new DataTransfer();
          dataTransfer.items.add(file);
          input.files = dataTransfer.files;
          stopStream();
          show(video, false);
          show(canvas, true);
          show(takeBtn, false);
          show(retakeBtn, true);
          updateSubmit();
          message.textContent = "Looking good? If it's blurry or cut off, retake it.";
        },
        "image/jpeg",
        0.92
      );
    });

    retakeBtn.addEventListener("click", () => {
      input.value = "";
      updateSubmit();
      openBtn.click();
    });

    window.addEventListener("pagehide", stopStream);
  });
});
