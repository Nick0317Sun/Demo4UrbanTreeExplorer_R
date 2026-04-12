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

function getAssistantElements() {
  return {
    input: document.getElementById("assistant_input"),
    sendButton: document.getElementById("assistant_send")
  };
}

function clickAssistantSend() {
  var els = getAssistantElements();
  if (els.sendButton && !els.sendButton.disabled) {
    els.sendButton.click();
  }
}

function submitAssistantFromKeyboard() {
  var els = getAssistantElements();
  if (!els.input || !window.Shiny || els.input.disabled) {
    return;
  }

  window.Shiny.setInputValue(
    "assistant_submit",
    {
      text: els.input.value,
      nonce: Date.now()
    },
    { priority: "event" }
  );
}

function scrollAssistantHistory(force) {
  var history = document.getElementById("assistant-history");
  if (!history) {
    return;
  }

  var nearBottom = history.scrollHeight - history.scrollTop - history.clientHeight < 32;
  if (!force && !nearBottom) {
    return;
  }

  var scrollToBottom = function () {
    history.scrollTop = history.scrollHeight;
  };

  scrollToBottom();
  window.setTimeout(scrollToBottom, 0);
  window.setTimeout(scrollToBottom, 40);
  window.setTimeout(scrollToBottom, 120);
}

function ensureAssistantHistoryObserver() {
  var history = document.getElementById("assistant-history");
  if (!history || history.__assistantObserverAttached) {
    return;
  }

  history.__assistantObserverAttached = true;
  var observer = new MutationObserver(function (mutations) {
    var hasRelevantChange = mutations.some(function (mutation) {
      return mutation.type === "childList" && (mutation.addedNodes.length > 0 || mutation.removedNodes.length > 0);
    });
    if (hasRelevantChange) {
      scrollAssistantHistory(true);
    }
  });

  observer.observe(history, { childList: true, subtree: true });
}

document.addEventListener("keydown", function (event) {
  var target = event.target;
  if (!target || target.id !== "assistant_input") {
    return;
  }

  if (event.isComposing) {
    return;
  }

  if (event.key === "Enter" && !event.shiftKey) {
    event.preventDefault();
    submitAssistantFromKeyboard();
  }
});

document.addEventListener("DOMContentLoaded", function () {
  ensureAssistantHistoryObserver();
  scrollAssistantHistory(true);
});

function registerAssistantHandlers() {
  if (!window.Shiny || window.__assistantHandlersRegistered) {
    return;
  }

  window.__assistantHandlersRegistered = true;

  Shiny.addCustomMessageHandler("assistant:set-state", function (message) {
    var els = getAssistantElements();
    if (els.input) {
      els.input.disabled = !!message.disabled;
      if (typeof message.placeholder === "string") {
        els.input.placeholder = message.placeholder;
      }
    }
    if (els.sendButton) {
      els.sendButton.disabled = !!message.disabled;
      if (typeof message.button_label === "string") {
        els.sendButton.textContent = message.button_label;
      }
    }
  });

  Shiny.addCustomMessageHandler("assistant:focus-input", function () {
    var els = getAssistantElements();
    if (els.input && !els.input.disabled) {
      window.setTimeout(function () {
        els.input.focus();
      }, 0);
    }
  });

  Shiny.addCustomMessageHandler("assistant:scroll-history", function (message) {
    ensureAssistantHistoryObserver();
    scrollAssistantHistory(!!(message && message.force));
  });
}

registerAssistantHandlers();
document.addEventListener("shiny:connected", registerAssistantHandlers);
document.addEventListener("shiny:value", ensureAssistantHistoryObserver);
