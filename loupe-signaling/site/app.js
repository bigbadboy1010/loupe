(function () {
  "use strict";

  var STATUS_RESET_MS = 6000;
  var EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

  function setStatus(form, message, kind) {
    var status = document.getElementById(form.dataset.statusId);
    if (!status) return;
    status.textContent = message;
    status.classList.remove("is-error", "is-success");
    if (kind) status.classList.add("is-" + kind);
    if (message && kind === "success") {
      window.setTimeout(function () {
        status.textContent = "";
      }, STATUS_RESET_MS);
    }
  }

  function setLoading(form, isLoading) {
    form.classList.toggle("is-loading", isLoading);
    var button = form.querySelector("button[type='submit']");
    var input = form.querySelector("input[type='email']");
    if (button) button.disabled = isLoading;
    if (input) input.disabled = isLoading;
  }

  async function submit(form) {
    var input = form.querySelector("input[type='email']");
    var email = (input && input.value || "").trim();
    if (!EMAIL_RE.test(email)) {
      setStatus(form, "That doesn't look like a valid email address.", "error");
      if (input) input.focus();
      return;
    }

    setLoading(form, true);
    setStatus(form, "", null);

    try {
      var response = await fetch("/waitlist", {
        method: "POST",
        headers: { "content-type": "application/json", accept: "application/json" },
        body: JSON.stringify({ email: email, source: "landing", referrer: location.pathname }),
      });

      var payload = null;
      try {
        payload = await response.json();
      } catch (e) {
        payload = null;
      }

      if (response.ok) {
        setStatus(
          form,
          (payload && payload.message) || "You're on the list. We'll be in touch.",
          "success"
        );
        form.reset();
      } else if (response.status === 429) {
        setStatus(
          form,
          "Too many attempts from this network. Try again in a minute.",
          "error"
        );
      } else if (response.status === 409) {
        setStatus(form, "You're already on the list. We'll be in touch.", "success");
      } else {
        setStatus(
          form,
          (payload && payload.message) || "Something went wrong. Please try again.",
          "error"
        );
      }
    } catch (err) {
      setStatus(
        form,
        "Network error. Check your connection and try again.",
        "error"
      );
    } finally {
      setLoading(form, false);
    }
  }

  function wireForm(form) {
    form.dataset.statusId = form.getAttribute("aria-describedby") || "";
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      void submit(form);
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    var forms = document.querySelectorAll("form.waitlist");
    for (var i = 0; i < forms.length; i++) wireForm(forms[i]);
  });
})();
