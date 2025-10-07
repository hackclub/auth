// Get the current theme that was already set in the head
const savedTheme = localStorage.getItem("theme") || "light";

function updateIcon(theme) {
    const icons = document.querySelectorAll(".lightswitch-icon");
    icons.forEach(icon => {
        icon.textContent = theme === "dark" ? "💡" : "🌙";
    });
}

// Set initial icon and show all lightswitch buttons after theme is set
updateIcon(savedTheme);
const lightswitchButtons = document.querySelectorAll(".lightswitch-btn");
lightswitchButtons.forEach(btn => {
    btn.classList.add("theme-loaded");
});

// Add click handler to all lightswitch buttons
lightswitchButtons.forEach(btn => {
    btn.addEventListener("click", () => {
        const theme = document.body.parentElement.dataset.theme === "dark" ? "light" : "dark";
        document.body.parentElement.dataset.theme = theme;
        localStorage.setItem("theme", theme);
        updateIcon(theme);
    });
});