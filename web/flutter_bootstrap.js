{{flutter_js}}
{{flutter_build_config}}

(async () => {
  const fallback = document.getElementById('app-fallback');
  const fallbackMessage = document.getElementById('fallback-message');
  const fallbackBar = document.getElementById('fallback-bar');

  const setProgress = (pct, text) => {
    if (fallbackBar) fallbackBar.style.width = pct + '%';
    if (fallbackMessage && text) fallbackMessage.textContent = text;
  };

  const showFallbackError = () => {
    setProgress(100, 'Could not start RIG-CAR. Refresh this page to try again.');
    if (fallbackBar) fallbackBar.style.background = '#ef4444';
  };

  // Wait for two frames so Flutter's first painted frame lands before the
  // splash disappears, otherwise the canvas flashes empty for a moment.
  const nextFrames = () => new Promise((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(resolve));
  });

  setProgress(28, 'Preparing workspace…');

  // Remove service workers left by older deployments so stale Flutter assets
  // cannot keep the app on a blank screen after a GitHub Pages update.
  const hadController = Boolean(navigator.serviceWorker?.controller);
  try {
    if ('serviceWorker' in navigator) {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations.map((registration) => registration.unregister()));
    }

    if ('caches' in window) {
      const cacheNames = await caches.keys();
      await Promise.all(cacheNames.map((name) => caches.delete(name)));
    }
  } catch (_) {
    // The app can still load when storage APIs are unavailable.
  }

  if (hadController && !sessionStorage.getItem('rig-car-sw-cleared')) {
    sessionStorage.setItem('rig-car-sw-cleared', 'true');
    window.location.reload();
    return;
  }

  // Force-bust main.dart.js caching so the browser never serves stale JS.
  const buildTag = 'build_' + Date.now();
  if (window._flutter?.buildConfig?.builds) {
    for (const build of window._flutter.buildConfig.builds) {
      if (build.mainJsPath) {
        build.mainJsPath = build.mainJsPath.split('?')[0] + '?v=' + buildTag;
      }
    }
  }

  try {
    setProgress(52, 'Loading Flutter engine…');
    await _flutter.loader.load({
      config: {
        entrypointUrl: 'main.dart.js?v=' + buildTag,
      },
      onEntrypointLoaded: async (engineInitializer) => {
        setProgress(78, 'Initializing 3D studio…');
        const appRunner = await engineInitializer.initializeEngine();
        setProgress(96, 'Launching RIG-CAR…');
        await appRunner.runApp();
        await nextFrames();
        setProgress(100, 'Ready');
        if (fallback) {
          fallback.classList.add('fade-out');
          setTimeout(() => fallback.remove(), 280);
        }
      },
    });
  } catch (_) {
    showFallbackError();
  }
})();
