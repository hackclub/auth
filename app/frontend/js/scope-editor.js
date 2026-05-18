const YSWS_DEFAULT_SCOPES = ['name', 'birthdate', 'address', 'basic_info', 'verification_status'];

export function scopeEditor({ trustLevel, selectedScopes, allowedScopes, communityScopes, allScopes, yswsDefaults }) {
  return {
    trustLevel,
    selected: [...selectedScopes],
    removedScopes: [],
    showYswsDefaults: yswsDefaults || false,

    get editableScopes() {
      const pool = this.trustLevel === 'hq_official' ? allowedScopes : communityScopes;
      return allScopes.filter(s => pool.includes(s.name));
    },

    // Scopes on the app that this user can't touch — rendered as locked rows
    // with hidden inputs so they're preserved on save.
    // Uses the *original* selectedScopes (closure over init arg) so a locked
    // scope stays locked even if Alpine state is manipulated.
    get lockedScopes() {
      const editableNames = this.editableScopes.map(s => s.name);
      return allScopes.filter(s =>
        selectedScopes.includes(s.name) && !editableNames.includes(s.name)
      );
    },

    isChecked(name) { return this.selected.includes(name); },

    toggle(name) {
      const i = this.selected.indexOf(name);
      if (i >= 0) this.selected.splice(i, 1);
      else this.selected.push(name);
    },

    onTrustLevelChange() {
      // Determine which scopes are valid for the new trust level,
      // scoped to what this user is allowed to touch.
      const trustValid = this.trustLevel === 'hq_official' ? allowedScopes : communityScopes;
      this.removedScopes = this.selected.filter(s =>
        allowedScopes.includes(s) && !trustValid.includes(s)
      );
      this.selected = this.selected.filter(s =>
        trustValid.includes(s) || !allowedScopes.includes(s)
      );
    },

    dismissWarning() { this.removedScopes = []; },

    applyYswsDefaults() {
      this.trustLevel = 'hq_official';
      this.removedScopes = [];
      const valid = this.editableScopes.map(s => s.name);
      this.selected = YSWS_DEFAULT_SCOPES.filter(s => valid.includes(s));
    },
  };
}
