document.querySelector('button').onclick = async () => {
  const [tab] = await chrome.tabs.query({active:true,currentWindow:true});
  if (!tab?.url || new URL(tab.url).hostname !== 'localhost') return;
  const [result] = await chrome.scripting.executeScript({target:{tabId:tab.id},func:()=>getSelection().toString()});
  document.querySelector('output').textContent = result.result || 'No selection';
};
