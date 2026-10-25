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
      await Promise.all(
        cacheNames
            .filter((name) => name.includes('flutter-app-cache'))
            .map((name) => caches.delete(name)),
      );
    }
  } catch (_) {
    // The app can still load when storage APIs are unavailable.
  }

  if (hadController && !sessionStorage.getItem('rig-car-sw-cleared')) {
    sessionStorage.setItem('rig-car-sw-cleared', 'true');
    window.location.reload();
    return;
  }

  try {
    await _flutter.loader.load({
      config: {
        // Keep CanvasKit assets on the same GitHub Pages origin as the app.
        canvasKitBaseUrl: './canvaskit/',
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
