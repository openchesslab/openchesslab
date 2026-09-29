module.exports = {
  content: ["../lib/**/*.{ex,heex}", "./js/**/*.js"],
  theme: {
    extend: {
      colors: {
        canvas: "var(--canvas)",
        panel: "var(--panel)",
        "panel-hover": "var(--panel-hover)",
        border: "var(--border)",
        "border-strong": "var(--border-strong)",
        foreground: "var(--foreground)",
        muted: "var(--muted)",
        faint: "var(--faint)",
        accent: "rgb(var(--accent-rgb) / <alpha-value>)",
        "accent-strong": "var(--accent-strong)",
        highlight: "rgb(var(--highlight-rgb) / <alpha-value>)",
        focus: "var(--focus)",
        error: "rgb(var(--error-rgb) / <alpha-value>)",
        success: "rgb(var(--success-rgb) / <alpha-value>)",
        warning: "rgb(var(--warning-rgb) / <alpha-value>)",
        "board-light": "#ebecd0",
        "board-dark": "#779556",
        "board-move-from": "#cdd26a",
        "board-move-to": "#aaa23a",
      },
      fontFamily: {
        sans: ["Open Sans", "system-ui", "sans-serif"],
        mono: ["ui-monospace", "SFMono-Regular", "monospace"],
      },
      boxShadow: {
        panel: "0 12px 40px rgba(0, 0, 0, .35)",
      },
    },
  },
  plugins: [],
};
