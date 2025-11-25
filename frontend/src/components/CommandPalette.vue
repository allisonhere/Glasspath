<template>
  <n-modal
    v-model:show="openInternal"
    preset="card"
    class="command-palette"
    :bordered="false"
    :closable="false"
    :mask-closable="true"
    :transform-origin="'center'"
    @after-leave="reset"
  >
    <div class="command-palette__body">
      <n-input
        ref="inputRef"
        v-model:value="query"
        size="large"
        clearable
        :placeholder="placeholder"
        @keydown.stop
        @keydown.enter.prevent="runSelected"
        @keydown.arrow-down.prevent="move(1)"
        @keydown.arrow-up.prevent="move(-1)"
        @keydown.escape.prevent="close"
      />
      <div class="command-palette__list" role="listbox">
        <div
          v-for="(cmd, idx) in filtered"
          :key="cmd.id"
          class="command-palette__item"
          :class="{ active: idx === activeIndex, disabled: cmd.disabled }"
          role="option"
          :aria-selected="idx === activeIndex"
          @click="run(cmd)"
          @mouseenter="activeIndex = idx"
        >
          <div class="command-palette__title">
            <span>{{ cmd.label }}</span>
            <span v-if="cmd.shortcut" class="command-palette__shortcut">
              {{ cmd.shortcut }}
            </span>
          </div>
          <p v-if="cmd.description" class="command-palette__description">
            {{ cmd.description }}
          </p>
        </div>
        <div v-if="!filtered.length" class="command-palette__empty">
          {{ $t("files.noResults") || "No matches" }}
        </div>
      </div>
    </div>
  </n-modal>
</template>

<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { NInput, NModal } from "naive-ui";

const props = defineProps<{
  open: boolean;
  commands: Array<{
    id: string;
    label: string;
    description?: string;
    shortcut?: string;
    disabled?: boolean;
  }>;
  placeholder?: string;
}>();

const emit = defineEmits<{
  (e: "update:open", val: boolean): void;
  (e: "run", id: string): void;
}>();

const query = ref("");
const activeIndex = ref(0);
const inputRef = ref<InstanceType<typeof NInput> | null>(null);

const openInternal = computed({
  get: () => props.open,
  set: (val: boolean) => emit("update:open", val),
});

const filtered = computed(() => {
  if (!query.value) return props.commands.filter((c) => !c.disabled);
  const q = query.value.toLowerCase();
  return props.commands.filter((cmd) => {
    if (cmd.disabled) return false;
    return (
      cmd.label.toLowerCase().includes(q) ||
      cmd.description?.toLowerCase().includes(q)
    );
  });
});

const placeholder = computed(
  () => props.placeholder ?? "Type a command or search…"
);

const reset = () => {
  query.value = "";
  activeIndex.value = 0;
};

const close = () => {
  emit("update:open", false);
};

const run = (cmd: { id: string; disabled?: boolean }) => {
  if (cmd.disabled) return;
  emit("run", cmd.id);
  close();
};

const runSelected = () => {
  const cmd = filtered.value[activeIndex.value];
  if (cmd) run(cmd);
};

const move = (delta: number) => {
  if (!filtered.value.length) return;
  activeIndex.value =
    (activeIndex.value + delta + filtered.value.length) %
    filtered.value.length;
};

watch(
  () => props.open,
  (val) => {
    if (val) {
      nextTick(() => inputRef.value?.focus());
    } else {
      reset();
    }
  }
);
</script>
