<template>
  <n-config-provider
    :theme-overrides="themeOverrides"
    :inline-theme-disabled="true"
    abstract
  >
    <router-view></router-view>
  </n-config-provider>
</template>

<script setup lang="ts">
import { ref, onMounted, watch, computed, onBeforeUnmount } from "vue";
import { useI18n } from "vue-i18n";
import { NConfigProvider, type GlobalThemeOverrides } from "naive-ui";
import { setHtmlLocale } from "./i18n";
import { getMediaPreference, getTheme, setTheme } from "./utils/theme";

const { locale } = useI18n();

const userTheme = ref<UserTheme>(getTheme() || getMediaPreference());
const themeKey = ref<UserTheme>(userTheme.value);
const themeObserver = new MutationObserver(() => {
  themeKey.value = getTheme() || getMediaPreference();
});

const readCssVar = (name: string, fallback: string) => {
  const styles = getComputedStyle(document.documentElement);
  const value = styles.getPropertyValue(name);
  if (!value || !value.trim()) return fallback;
  return value.trim();
};

const themeOverrides = computed<GlobalThemeOverrides>(() => {
  // re-compute when theme class changes
  themeKey.value;
  const primary = readCssVar("--primary", "#1dd1c0");
  const primaryStrong = readCssVar("--primary-strong", "#0ea89f");
  const textBase = readCssVar("--textSecondary", "#0f172a");
  const textMuted = readCssVar("--textPrimary", "#64748b");
  const surface = readCssVar("--surfacePrimary", "#ffffff");
  const surfaceSecondary = readCssVar("--surfaceSecondary", "#edf1f8");
  const border = readCssVar("--borderPrimary", "rgba(15, 23, 42, 0.06)");

  return {
    common: {
      primaryColor: primary,
      primaryColorHover: primaryStrong,
      primaryColorPressed: primaryStrong,
      primaryColorSuppl: primaryStrong,
      infoColor: primary,
      successColor: readCssVar("--icon-green", "#22c55e"),
      warningColor: readCssVar("--accent", "#ffb347"),
      errorColor: readCssVar("--red", "#ef4444"),
      textColorBase: textBase,
      textColor1: textBase,
      textColor2: textMuted,
      baseColor: surface,
      bodyColor: surface,
      cardColor: surface,
      modalColor: surface,
      popoverColor: surface,
      tableHeaderColor: surfaceSecondary,
      inputColor: surface,
      hoverColor: readCssVar("--hover", "rgba(31, 155, 240, 0.08)"),
      dividerColor: border,
      borderColor: border,
      borderColorHover: readCssVar("--borderSecondary", "rgba(15, 23, 42, 0.16)"),
    },
  };
});

onMounted(() => {
  setTheme(userTheme.value);
  setHtmlLocale(locale.value);
  themeObserver.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["class"],
  });
  // this might be null during HMR
  const loading = document.getElementById("loading");
  loading?.classList.add("done");

  setTimeout(function () {
    loading?.parentNode?.removeChild(loading);
  }, 200);
});

// handles ltr/rtl changes
watch(locale, (newValue) => {
  newValue && setHtmlLocale(newValue);
});

onBeforeUnmount(() => {
  themeObserver.disconnect();
});
</script>
