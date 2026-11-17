let installationToken;
function token() {
  return installationToken ??= (async () => {
    const {first} = await chrome.storage.local.get('first');
    if (first) return first;
    const value = crypto.randomUUID();
    await chrome.storage.local.set({first:value});
    return value;
  })();
}
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (message !== 'probe' || !sender.tab || !sender.url || new URL(sender.url).hostname !== 'localhost') return;
  Promise.all([token(), chrome.tabs.query({})]).then(([value, tabs]) => {
    reply({token:value, senderWindow:sender.tab.windowId, senderTab:sender.tab.id,
      tabs:tabs.map(({id,windowId,active}) => ({id,windowId,active}))});
  }).catch(() => reply(null));
  return true;
});
