// Cookies make the existing local preferences available to the first HTTP
// render, independently of the authentication cookie cleared at login/logout.
export function persistBrowserPreference(name, value) {
  const allowed = {
    theme: ["system", "light", "dark"],
    locale: ["en", "nl"],
  };
  if (!allowed[name]?.includes(value)) return;

  try {
    document.cookie = `_ocl_${name}=${value}; Path=/; Max-Age=31536000; SameSite=Lax${
      location.protocol === "https:" ? "; Secure" : ""
    }`;
  } catch (_) {
    // Presentation preferences must not break the UI when storage is blocked.
  }

  try {
    localStorage.setItem(`openchesslab:${name}`, value);
  } catch (_) {
    /* optional */
  }
}
