// Get the current theme that was already set in the head
const savedTheme = localStorage.getItem("theme") || "light";

function updateIcon(theme) {
    const buttons = document.querySelectorAll(".lightswitch-btn");
    buttons.forEach(btn => {
        const moonIcon = btn.querySelector(".lightswitch-moon");
        const sunIcon = btn.querySelector(".lightswitch-sun");
        
        if (moonIcon && sunIcon) {
            if (theme === "dark") {
                moonIcon.style.display = "none";
                sunIcon.style.display = "inline";
            } else {
                moonIcon.style.display = "inline";
                sunIcon.style.display = "none";
            }
        }
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