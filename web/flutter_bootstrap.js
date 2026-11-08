{{flutter_js}}
{{flutter_build_config}}

(async () => {
  const fallback = document.getElementById('app-fallback');
  const fallbackMessage = document.getElementById('fallback-message');

  const showFallbackError = () => {
    if (fallbackMessage) {
      fallbackMessage.textContent =
          'The dashboard could not start. Refresh this page to try again.';
    }
    document.querySelector('.fallback-spinner')?.remove();
  };

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

  // Force-bust main.dart.js caching so the browser never serves stale JS
  const buildTag = 'build_' + Date.now();
  if (window._flutter?.buildConfig?.builds) {
    for (const build of window._flutter.buildConfig.builds) {
      if (build.mainJsPath) {
        build.mainJsPath = build.mainJsPath.split('?')[0] + '?v=' + buildTag;
      }
    }
  }

  try {
    await _flutter.loader.load({
      config: {
        entrypointUrl: 'main.dart.js?v=' + buildTag,
      },
      onEntrypointLoaded: async (engineInitializer) => {
        const appRunner = await engineInitializer.initializeEngine();
        await appRunner.runApp();
        fallback?.remove();
      },
    });
  } catch (_) {
    showFallbackError();
  }
})();
