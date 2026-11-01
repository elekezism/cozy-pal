// Registers the offline cache (sw.js). A separate file, not an inline script,
// so the Content-Security-Policy can stay strict.
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js').catch(() => {});
  });
}
