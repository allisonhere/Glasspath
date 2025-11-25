import { theme } from "./constants";
import "ace-builds";
import { themesByName } from "ace-builds/src-noconflict/ext-themelist";

const supportedThemes: UserTheme[] = ["light", "dawn", "dark", "noir"];
const darkThemes: UserTheme[] = ["dark", "noir"];

const resolveThemeClass = (value: string | undefined | null): UserTheme => {
  if (!value) return "";
  const sanitized = value.trim();
  const matched = supportedThemes.find((t) => t === sanitized);
  return matched ?? "";
};

export const getTheme = (): UserTheme => {
  const classTheme = resolveThemeClass(document.documentElement.className);
  if (classTheme) return classTheme;
  const initialTheme = resolveThemeClass(theme);
  if (initialTheme) return initialTheme;
  return getMediaPreference();
};

export const setTheme = (value: UserTheme) => {
  const html = document.documentElement;
  if (!value) {
    html.className = getMediaPreference();
    return;
  }

  const newTheme = resolveThemeClass(value) || "light";
  html.className = newTheme;
};

export const isDarkTheme = (value: UserTheme = getTheme()): boolean => {
  return darkThemes.includes(value);
};

export const toggleTheme = (): void => {
  const paletteOrder: UserTheme[] = ["light", "dawn", "dark", "noir"];
  const activeTheme = getTheme();
  const idx = paletteOrder.indexOf(activeTheme);
  const nextTheme = paletteOrder[(idx + 1) % paletteOrder.length];
  setTheme(nextTheme);
};

export const getMediaPreference = (): UserTheme => {
  const hasDarkPreference = window.matchMedia(
    "(prefers-color-scheme: dark)"
  ).matches;
  if (hasDarkPreference) {
    return "dark";
  } else {
    return "light";
  }
};

export const getEditorTheme = (themeName: string) => {
  if (!themeName.startsWith("ace/theme/")) {
    themeName = `ace/theme/${themeName}`;
  }
  const themeKey = themeName.replace("ace/theme/", "");
  if (themesByName[themeKey] !== undefined) {
    return themeName;
  } else if (getTheme() === "dark") {
    return "ace/theme/twilight";
  } else {
    return "ace/theme/chrome";
  }
};
