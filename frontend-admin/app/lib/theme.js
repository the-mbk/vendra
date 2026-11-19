// ══════════════════════════════════════════════════════════════
// Vendra Admin Dashboard - Theme (light / dark)
// Plain module (no hooks) so the root layout can inline the init script.
// ══════════════════════════════════════════════════════════════

/** localStorage key holding "light" | "dark"; absent = follow the system setting */
export const THEME_STORAGE_KEY = "vendra_admin_theme";

/**
 * Runs in <head> before the first paint: adds the .dark class to <html> when the saved
 * choice (or, with none saved, the system setting) is dark, so pages never flash light.
 */
export const themeInitScript = `(function(){try{var t=null;try{t=localStorage.getItem(${JSON.stringify(
  THEME_STORAGE_KEY
)})}catch(e){}var d=t?t==="dark":window.matchMedia("(prefers-color-scheme: dark)").matches;document.documentElement.classList.toggle("dark",d)}catch(e){}})();`;
