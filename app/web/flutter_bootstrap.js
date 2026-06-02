{{flutter_js}}
{{flutter_build_config}}

const loadApp = () => {
  _flutter.loader.load();
};

if ('serviceWorker' in navigator) {
  navigator.serviceWorker
    .getRegistrations()
    .then((registrations) => {
      return Promise.all(
        registrations.map((registration) => registration.unregister()),
      );
    })
    .catch(() => {})
    .finally(loadApp);
} else {
  loadApp();
}
