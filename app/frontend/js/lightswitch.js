// Get the current theme that was already set in the head
const savedTheme = localStorage.getItem("theme") || "light";

function updateIcon(theme) {
    const icon = document.querySelector(".lightswitch-icon");
    if (icon) {
        icon.textContent = theme === "dark" ? "💡" : "🌙";
    }
}

// Set initial icon and show button after theme is set
updateIcon(savedTheme);
const lightswitchBtn = document.getElementById("lightswitch");
if (lightswitchBtn) {
    lightswitchBtn.classList.add("theme-loaded");
}

document.getElementById("lightswitch").addEventListener("click", () => {
    const theme = document.body.parentElement.dataset.theme === "dark" ? "light" : "dark";
    document.body.parentElement.dataset.theme = theme;
    localStorage.setItem("theme", theme);
    updateIcon(theme);
});