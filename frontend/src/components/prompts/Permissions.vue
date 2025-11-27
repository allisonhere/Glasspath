<template>
  <div class="card floating">
    <div class="card-title">
      <h2>{{ $t("prompts.permissions") }}</h2>
    </div>

    <div class="card-content">
      <p class="mb-4">
        {{ selectionLabel }}
      </p>

      <label class="label" :for="'permissions-mode'">
        {{ $t("prompts.permissionsMode") }}
      </label>
      <input
        id="permissions-mode"
        class="input input--block"
        type="text"
        inputmode="numeric"
        autocomplete="off"
        spellcheck="false"
        v-model.trim="mode"
        :placeholder="$t('prompts.permissionsModePlaceholder')"
      />

      <div>
        <label class="label" :for="'permissions-owner'">
          {{ $t("prompts.permissionsOwner") }}
        </label>
        <input
          id="permissions-owner"
          class="input input--block"
          type="text"
          autocomplete="off"
          spellcheck="false"
          v-model.trim="owner"
          :placeholder="$t('prompts.permissionsOwnerPlaceholder')"
        />
      </div>

      <div>
        <label class="label" :for="'permissions-group'">
          {{ $t("prompts.permissionsGroup") }}
        </label>
        <input
          id="permissions-group"
          class="input input--block"
          type="text"
          autocomplete="off"
          spellcheck="false"
          v-model.trim="group"
          :placeholder="$t('prompts.permissionsGroupPlaceholder')"
        />
      </div>

      <label class="checkbox">
        <input type="checkbox" v-model="recursive" />
        <span>{{ $t("prompts.permissionsRecursive") }}</span>
      </label>
      <p class="help">
        {{ $t("prompts.permissionsHint") }}
      </p>
    </div>

    <div class="card-action">
      <button
        class="button button--flat button--grey"
        @click="closeHovers"
        :aria-label="$t('buttons.cancel')"
        :title="$t('buttons.cancel')"
      >
        {{ $t("buttons.cancel") }}
      </button>
      <button
        id="permissions-button"
        class="button button--flat"
        type="submit"
        @click="submit"
        :aria-label="$t('buttons.permissions')"
        :title="$t('buttons.permissions')"
      >
        {{ $t("buttons.permissions") }}
      </button>
    </div>
  </div>
</template>

<script>
import { mapActions, mapState, mapWritableState } from "pinia";
import { files as api } from "@/api";
import { useFileStore } from "@/stores/file";
import { useLayoutStore } from "@/stores/layout";

export default {
  name: "permissions",
  inject: ["$showError"],
  data: () => ({
    mode: "",
    owner: "",
    group: "",
    recursive: false,
  }),
  computed: {
    ...mapState(useFileStore, [
      "req",
      "selected",
      "selectedCount",
      "isListing",
    ]),
    ...mapWritableState(useFileStore, ["reload"]),
    selectionLabel() {
      if (!this.isListing || this.selectedCount === 0) {
        return this.$t("prompts.permissionsSingle");
      }
      if (this.selectedCount === 1) {
        const item = this.req?.items[this.selected[0]];
        return this.$t("prompts.permissionsSingleName", { name: item?.name });
      }
      return this.$t("prompts.permissionsMultiple", {
        count: this.selectedCount,
      });
    },
  },
  created() {
    this.prefill();
  },
  methods: {
    ...mapActions(useLayoutStore, ["closeHovers"]),
    prefill() {
      const target = this.getFirstTarget();
      if (!target) return;

      const mode = (target.mode ?? 0) & 0o777;
      this.mode = mode.toString(8).padStart(3, "0");
      this.owner = target.owner || (typeof target.uid === "number" ? `${target.uid}` : "");
      this.group = target.group || (typeof target.gid === "number" ? `${target.gid}` : "");
      this.recursive = !!target.isDir;
    },
    getTargets() {
      if (!this.isListing && this.req) {
        return [this.req];
      }
      if (!this.req || this.selectedCount === 0) {
        return [];
      }
      return this.selected.map((i) => this.req.items[i]);
    },
    getFirstTarget() {
      const targets = this.getTargets();
      if (targets.length > 0) return targets[0];
      return this.req;
    },
    async submit() {
      if (
        this.mode.trim() === "" &&
        this.owner.trim() === "" &&
        this.group.trim() === ""
      ) {
        this.$showError(new Error(String(this.$t("prompts.permissionsValidation"))));
        return;
      }

      const targets = this.getTargets();
      if (targets.length === 0) {
        this.$showError(new Error(String(this.$t("prompts.permissionsValidation"))));
        return;
      }

      const payload = {
        recursive: this.recursive,
      };

      if (this.mode.trim()) payload.mode = this.mode.trim();
      if (this.owner.trim()) payload.owner = this.owner.trim();
      if (this.group.trim()) payload.group = this.group.trim();

      try {
        const promises = targets.map((item) =>
          api.changePermissions(item.url, payload)
        );
        await Promise.all(promises);
        this.reload = true;
      } catch (e) {
        this.$showError(e);
        return;
      }

      this.closeHovers();
    },
  },
};
</script>
