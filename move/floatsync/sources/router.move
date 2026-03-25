module floatsync::router {
    use floatsync::merchant::AdminCap;
    use floatsync::events;

    // ── Router modes ──
    const MODE_FALLBACK: u8 = 0;
    // const MODE_STABLELAYER: u8 = 1; // Future: StableLayer yield routing

    // ── Error codes ──
    const EInvalidMode: u64 = 20;
    const ESameMode: u64 = 21;

    /// Shared config object controlling payment routing strategy.
    /// MODE_FALLBACK (0): payments go directly to merchant, no yield.
    /// Future modes will route idle_principal to yield protocols.
    public struct RouterConfig has key {
        id: UID,
        mode: u8,
    }

    // ── Init ──

    /// Creates RouterConfig in fallback mode. Called once at package publish.
    fun init(ctx: &mut TxContext) {
        transfer::share_object(RouterConfig {
            id: object::new(ctx),
            mode: MODE_FALLBACK,
        });
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // ── Admin functions ──

    /// Change router mode. Requires AdminCap.
    /// Currently only mode 0 (fallback) is valid. Future: mode 1 (StableLayer).
    public fun set_mode(
        _admin: &AdminCap,
        config: &mut RouterConfig,
        new_mode: u8,
    ) {
        assert!(new_mode <= MODE_FALLBACK, EInvalidMode); // tighten when adding modes
        assert!(new_mode != config.mode, ESameMode);
        let old_mode = config.mode;
        config.mode = new_mode;
        events::emit_router_mode_changed(old_mode, new_mode);
    }

    // ── Getters ──

    public fun get_mode(config: &RouterConfig): u8 { config.mode }
    public fun is_fallback(config: &RouterConfig): bool { config.mode == MODE_FALLBACK }
}
