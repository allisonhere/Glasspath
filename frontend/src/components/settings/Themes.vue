<template>
  <n-select
    :value="theme"
    :options="themeOptions"
    size="large"
    :consistent-menu-width="false"
    @update:value="onUpdate"
  />
</template>

<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";

const { t } = useI18n();

defineProps<{
  theme: UserTheme;
}>();

const emit = defineEmits<{
  (e: "update:theme", val: string | null): void;
}>();

const themeOptions = computed(() => [
  { value: "", label: t("settings.themes.default") },
  { value: "light", label: t("settings.themes.light") },
  { value: "dawn", label: t("settings.themes.dawn") },
  { value: "dark", label: t("settings.themes.dark") },
  { value: "noir", label: t("settings.themes.noir") },
  { value: "glass", label: t("settings.themes.glass") },
  { value: "pro", label: t("settings.themes.pro") },
]);

const onUpdate = (value: string | null) => {
  emit("update:theme", value);
};
</script>
