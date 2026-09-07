#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_log_to_console(if cfg!(debug_assertions) {
        log::LevelFilter::Trace
    } else {
        log::LevelFilter::Warn
    });
    flutter_rust_bridge::setup_backtrace();
}

// Initializes and deinitializes the rustls-platform-verifier
// on Android.
#[cfg(target_os = "android")]
mod init_android_context {
    use std::{
        os::raw::c_void,
        sync::{
            atomic::{AtomicBool, Ordering},
            Arc, OnceLock,
        },
    };

    use jni::{
        jni_mangle,
        objects::{JClass, JObject},
        refs::Global,
        EnvUnowned,
    };

    static CTX: OnceLock<Arc<Global<JObject>>> = OnceLock::new();
    static INITIALIZED: AtomicBool = AtomicBool::new(false);

    #[jni_mangle("com.flutter_rust_bridge.rhttp.RhttpPlugin")]
    pub extern "system" fn init_android<'caller>(
        mut unowned_env: EnvUnowned<'caller>,
        _class: JClass<'caller>,
        context: JObject<'caller>,
    ) {
        unowned_env
            .with_env(|env| {
                // `ndk_context::initialize_android_context` and
                // `rustls_platform_verifier` must run exactly once per process:
                // ndk_context asserts the context has not already been set (it
                // aborts with `assertion failed: previous.is_none()` otherwise).
                //
                // The plugin is attached to *every* FlutterEngine, so a second
                // engine in the same process — e.g. a background isolate spawned
                // by workmanager or background_fetch — would previously re-run
                // this init and crash the whole app. `swap` atomically lets only
                // the first attach perform the native initialization, even if two
                // engines attach concurrently on different threads. ndk_context is
                // process-global, so that single init serves every engine.
                if INITIALIZED.swap(true, Ordering::AcqRel) {
                    return Ok::<(), jni::errors::Error>(());
                }

                let jvm = env.get_java_vm().expect("Failed to get Java VM.");
                let jvm_pointer = jvm.get_raw() as *mut c_void;

                let global_ref = Arc::new(env.new_global_ref(&context)?);
                let _ = CTX.set(global_ref.clone());

                unsafe {
                    ndk_context::initialize_android_context(
                        jvm_pointer,
                        global_ref.as_obj().as_raw() as _,
                    );
                }

                rustls_platform_verifier::android::init_with_env(env, context)?;

                Ok::<(), jni::errors::Error>(())
            })
            .resolve::<jni::errors::ThrowRuntimeExAndDefault>();
    }

    #[jni_mangle("com.flutter_rust_bridge.rhttp.RhttpPlugin")]
    pub unsafe extern "system" fn deinit_android<'caller>(
        mut _unowned_env: EnvUnowned<'caller>,
        _class: JClass<'caller>,
    ) {
        // Intentionally a no-op. `init_android` initializes the process-global
        // ndk_context exactly once and other FlutterEngines in the same process
        // rely on it, so releasing it when a single engine detaches would break
        // the others (and a later re-attach would not re-initialize it). The
        // context is reclaimed when the process exits.
    }
}
