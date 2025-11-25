<template>
  <div class="card floating info-panel">
    <div class="info-panel__header">
      <div>
        <p class="info-panel__eyebrow">
          {{ dir ? $t("prompts.folder") : $t("prompts.file") }}
        </p>
        <h2>{{ $t("prompts.fileInfo") }}</h2>
      </div>
      <div class="info-panel__pill" v-if="selected.length">
        <i class="material-icons">layers</i>
        <span>{{ $t("prompts.filesSelected", { count: selected.length }) }}</span>
      </div>
    </div>

    <div class="info-panel__body">
      <div class="info-panel__row">
        <div class="info-panel__item" v-if="selected.length < 2">
          <span class="info-panel__label">{{ $t("prompts.displayName") }}</span>
          <span class="info-panel__value break-word">{{ name }}</span>
        </div>
        <div class="info-panel__item">
          <span class="info-panel__label">{{ $t("prompts.size") }}</span>
          <span class="info-panel__value">{{ humanSize }}</span>
        </div>
        <div class="info-panel__item" v-if="permValue">
          <span class="info-panel__label">{{ $t("prompts.permissions") }}</span>
          <span class="info-panel__value">{{ permValue }}</span>
        </div>
        <div class="info-panel__item" v-if="selected.length < 2">
          <span class="info-panel__label">{{ $t("prompts.lastModified") }}</span>
          <span class="info-panel__value" :title="modTime">{{ humanTime }}</span>
        </div>
        <div class="info-panel__item" v-if="resolution">
          <span class="info-panel__label">{{ $t("prompts.resolution") }}</span>
          <span class="info-panel__value"
            >{{ resolution.width }} × {{ resolution.height }}</span
          >
        </div>
        <div class="info-panel__item" v-if="dir && selected.length === 0">
          <span class="info-panel__label">{{ $t("prompts.numberFiles") }}</span>
          <span class="info-panel__value">{{ req.numFiles }}</span>
        </div>
        <div class="info-panel__item" v-if="dir && selected.length === 0">
          <span class="info-panel__label">{{ $t("prompts.numberDirs") }}</span>
          <span class="info-panel__value">{{ req.numDirs }}</span>
        </div>
      </div>

      <div class="info-panel__checks" v-if="!dir">
        <p class="info-panel__label">{{ $t("prompts.checksums") }}</p>
        <div class="info-panel__chips">
          <n-button
            v-for="algo in hashes"
            :key="algo"
            size="small"
            quaternary
            @click="checksum($event, algo)"
            @keypress.enter="checksum($event, algo)"
            tabindex="0"
          >
            <span class="info-panel__chip-label">{{ algo.toUpperCase() }}</span>
            <span class="info-panel__chip-value">{{ $t("prompts.show") }}</span>
          </n-button>
        </div>
      </div>
    </div>

    <div class="info-panel__footer card-action">
      <n-button
        id="focus-prompt"
        type="primary"
        block
        strong
        @click="closeHovers"
        :aria-label="$t('buttons.ok')"
        :title="$t('buttons.ok')"
      >
        {{ $t("buttons.ok") }}
      </n-button>
    </div>
  </div>
</template>

<script>
import { mapActions, mapState } from "pinia";
import { useFileStore } from "@/stores/file";
import { useLayoutStore } from "@/stores/layout";
import { filesize } from "@/utils";
import dayjs from "dayjs";
import { files as api } from "@/api";

export default {
  name: "info",
  inject: ["$showError"],
  computed: {
    ...mapState(useFileStore, [
      "req",
      "selected",
      "selectedCount",
      "isListing",
    ]),
    humanSize: function () {
      if (this.selectedCount === 0 || !this.isListing) {
        return filesize(this.req.size);
      }

      let sum = 0;

      for (const selected of this.selected) {
        sum += this.req.items[selected].size;
      }

      return filesize(sum);
    },
    humanTime: function () {
      if (this.selectedCount === 0) {
        return dayjs(this.req.modified).fromNow();
      }

      return dayjs(this.req.items[this.selected[0]].modified).fromNow();
    },
    modTime: function () {
      if (this.selectedCount === 0) {
        return new Date(Date.parse(this.req.modified)).toLocaleString();
      }

      return new Date(
        Date.parse(this.req.items[this.selected[0]].modified)
      ).toLocaleString();
    },
    name: function () {
      return this.selectedCount === 0
        ? this.req.name
        : this.req.items[this.selected[0]].name;
    },
    dir: function () {
      return (
        this.selectedCount > 1 ||
        (this.selectedCount === 0
          ? this.req.isDir
          : this.req.items[this.selected[0]].isDir)
      );
    },
    resolution: function () {
      if (this.selectedCount === 1) {
        const selectedItem = this.req.items[this.selected[0]];
        if (selectedItem && selectedItem.type === "image") {
          return selectedItem.resolution;
        }
      } else if (this.req && this.req.type === "image") {
        return this.req.resolution;
      }
      return null;
    },
    permValue: function () {
      const mode = this.selectedCount
        ? this.req.items[this.selected[0]].mode
        : this.req.mode;
      if (mode === undefined || mode === null) return "";
      return `${this.formatPerm(mode)} (${this.formatOctal(mode)})`;
    },
    hashes() {
      return ["md5", "sha1", "sha256", "sha512"];
    },
  },
  methods: {
    ...mapActions(useLayoutStore, ["closeHovers"]),
    formatOctal(mode) {
      return (mode & 0o7777).toString(8).padStart(4, "0");
    },
    formatPerm(mode) {
      const triplet = (val) =>
        `${val & 4 ? "r" : "-"}${val & 2 ? "w" : "-"}${val & 1 ? "x" : "-"}`;
      const bits = mode & 0o777;
      return `${triplet(bits >> 6)} ${triplet((bits >> 3) & 7)} ${triplet(
        bits & 7
      )}`;
    },
    checksum: async function (event, algo) {
      event.preventDefault();

      let link;

      if (this.selectedCount) {
        link = this.req.items[this.selected[0]].url;
      } else {
        link = this.$route.path;
      }

      try {
        const hash = await api.checksum(link, algo);
        event.target.textContent = hash;
      } catch (e) {
        this.$showError(e);
      }
    },
  },
};
</script>
