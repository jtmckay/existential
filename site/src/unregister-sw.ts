export function onClientEntry() {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.getRegistrations().then((regs) => {
      for (const reg of regs) {
        if (reg.scope.startsWith(window.location.origin)) {
          reg.unregister();
        }
      }
    });
  }
}
