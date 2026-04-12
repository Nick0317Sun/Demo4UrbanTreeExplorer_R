document.addEventListener("click", function (event) {
  var toggle = event.target.closest(".panel-toggle");
  if (!toggle) {
    return;
  }

  var targetClass = toggle.getAttribute("data-target");
  var panel = document.querySelector("." + targetClass);
  if (!panel) {
    return;
  }

  panel.classList.toggle("is-collapsed");
  var expanded = !panel.classList.contains("is-collapsed");
  toggle.setAttribute("aria-expanded", expanded ? "true" : "false");
  toggle.textContent = expanded ? "Collapse" : "Expand";
});
