globalThis.fixtureIsolatedMarker = true;
chrome.runtime.sendMessage('probe').then(result => {
  if (!result) return;
  document.documentElement.dataset.fixtureExtension = result.token;
  document.documentElement.dataset.fixtureTopology = JSON.stringify({senderTab:result.senderTab,senderWindow:result.senderWindow,tabs:result.tabs});
  document.dispatchEvent(new Event('fixture-response'));
});
